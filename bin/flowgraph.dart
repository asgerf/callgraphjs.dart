library jscallgraphs;

import 'package:parsejs/parsejs.dart';
import 'dart:math';

class FlowNode {
  List<FlowNode> predecessors = <FlowNode>[];
  
  FunctionNode function;
  CallExpression call;
  List<String> natives = <String>[];
  
  void flowTo(FlowNode other) {
    other.predecessors.add(this);
  }
}

class Numberer<T> {
  Map<T, int> map = <T, int>{};
  int nextId = 0;
  
  int makeFresh() => ++nextId;
  int operator[](T x) => map.putIfAbsent(x, makeFresh);
}

class FlowGraph {
  Map<Scope, Map<String, FlowNode>> variables = {};
  Map<String, FlowNode> fields = {};
  Map<FunctionNode, FlowNode> functions = {};
  Map<CallExpression, FlowNode> callees = {};
  List<FlowNode> nodes = <FlowNode>[];
  
  FlowNode global;
  
  FlowNode makeNode() {
    FlowNode node = new FlowNode();
    nodes.add(node);
    return node;
  }
  
  FlowGraph() {
    global = makeNode();
  }
  
  FlowNode getField(String name) => fields.putIfAbsent(name, makeNode);
  
  FlowNode getVariable(Scope scope, String name) {
    if (scope is Program) return getField(name);
    Map env = variables.putIfAbsent(scope, () => new Map());
    return env.putIfAbsent(name, makeNode);
  }
  
  FlowNode getVariableFromName(Name name) => getVariable(name.scope, name.value);
  FlowNode getFunction(FunctionNode node) => functions.putIfAbsent(node, () => makeNode()..function = node);
  FlowNode getCallee(CallExpression node) => callees.putIfAbsent(node, () => makeNode()..call = node);
  FlowNode getThis(FunctionNode node) => getVariable(node, '@this');
  FlowNode getReturn(FunctionNode node) => getVariable(node, '@return');
  
  void addEdge(FlowNode from, FlowNode to) {
    if (from == null || to == null) return;
    from.flowTo(to);
  }
  
  /// Returns a mixed list of FunctionNode and Strings, denoting user-defined and native call targets, respectively.
  List<dynamic> findCallTargets(CallExpression call) {
    List result = [];
    Set<FlowNode> seen = new Set<FlowNode>();
    void search(FlowNode node) {
      if (!seen.add(node)) return;
      if (node.function != null) {
        result.add(node.function);
      }
      result.addAll(node.natives);
      node.predecessors.forEach(search);
    }
    search(getCallee(call));
    return result;
  }
  
  String toDot() {
    StringBuffer sb = new StringBuffer();
    Numberer<FlowNode> ids = new Numberer<FlowNode>();
    sb.writeln('digraph {');
    for (FlowNode node in nodes) {
      List<String> labels = [];
      if (node.function != null) {
        labels.add('fn=${node.function.location}');
      }
      if (node.call != null) {
        labels.add('call=${node.call.location}');
      }
      String label = labels.join(' ');
      sb.writeln('  node ${ids[node]} [shape=box,label="$label"]');
      for (FlowNode pred in node.predecessors) {
        sb.writeln('  ${ids[pred]} -> ${ids[node]}');
      }
    }
    sb.writeln('}');
    return sb.toString();
  }
}

class FlowBuilder extends RecursiveVisitor<FlowNode> {
  
  FlowGraph graph;
  
  FlowBuilder([this.graph]) {
    if (graph == null) graph = new FlowGraph();
  }
  
  FlowNode visitFunctionNode(FunctionNode node) {
    visit(node.body);
    FlowNode self = graph.getFunction(node);
    if (node.name != null) {
      graph.addEdge(self, graph.getVariableFromName(node.name));
    }
    return self;
  }
  
  FlowNode visitFunctionExpression(FunctionExpression node) => visit(node.function);
  
  FlowNode visitNameExpression(NameExpression node) => graph.getVariableFromName(node.name);
  
  FlowNode visitSequence(SequenceExpression node) {
    FlowNode result = null;
    for (Expression exp in node.expressions) {
      result = visit(exp);
    }
    return result; // Return result from last subexpression
  }
  
  FlowNode visitBinary(BinaryExpression node) {
    switch (node.operator) {
      case '&&':
        visit(node.left);
        return visit(node.right);
      case '||':
        FlowNode join = graph.makeNode();
        graph.addEdge(visit(node.left), join);
        graph.addEdge(visit(node.right), join);
        return join;
      default:
        node.forEach(visit);
        return null;
    }
  }
  
  FlowNode visitAssignment(AssignmentExpression node) {
    if (node.operator == '=') {
      FlowNode left = visit(node.left);
      FlowNode right = visit(node.right);
      graph.addEdge(right, left);
      return right;
    } else {
      node.forEach(visit);
      return null;
    }
  }
  
  FlowNode visitConditional(ConditionalExpression node) {
    visit(node.condition);
    FlowNode join = graph.makeNode();
    graph.addEdge(visit(node.then), join);
    graph.addEdge(visit(node.otherwise), join);
    return join;
  }
  
  FlowNode visitCall(CallExpression node) {
    graph.addEdge(visit(node.callee), graph.getCallee(node));
    if (node.callee is FunctionExpression) {
      FunctionExpression callee = node.callee;
      FunctionNode function = callee.function;
      List<FlowNode> args = node.arguments.map(visit).toList();
      int numArgs = min(args.length, function.params.length);
      for (int i=0; i<numArgs; i++) {
        graph.addEdge(args[i], graph.getVariableFromName(function.params[i]));
      }
      return graph.getReturn(function);
    } else {
      node.arguments.forEach(visit);
      return null;
    }
  }
  
  FlowNode visitMember(MemberExpression node) {
    node.forEach(visit);
    return graph.getField(node.property.value);
  }
  
  visitReturn(ReturnStatement node) {
    if (node.argument != null) {
      FunctionNode function = node.enclosingFunction;
      if (function != null) {
        graph.addEdge(visit(node.argument), graph.getReturn(function));
      }
    }
  }
  
  visitVariableDeclarator(VariableDeclarator node) {
    if (node.init != null) {
      graph.addEdge(visit(node.init), graph.getVariableFromName(node.name));
    }
  }
  
}

FlowGraph buildFlowGraph(Program program) {
  return (new FlowBuilder()..visit(program)).graph;
}

