library jscallgraphs;

import 'package:parsejs/parsejs.dart';
import 'dart:math';


class FlowNode {
  List<FlowNode> predecessors = <FlowNode>[];
  
  FunctionNode function;
  CallExpression call;
  
  void flowTo(FlowNode other) {
    other.predecessors.add(this);
  }
}

class FlowGraph {
  Map<Scope, Map<String, FlowNode>> variables = {};
  Map<String, FlowNode> fields = {};
  Map<FunctionNode, FlowNode> functions = {};
  Map<CallExpression, FlowNode> callees = {};
  
  FlowNode global = new FlowNode();
  
  FlowNode makeNode() => new FlowNode();
  
  FlowNode getField(String name) => fields.putIfAbsent(name, makeNode);
  
  FlowNode getVariable(Scope scope, String name) {
    if (scope is Program) return getField(name);
    Map env = variables.putIfAbsent(scope, () => new Map());
    return env.putIfAbsent(name, makeNode);
  }
  
  FlowNode getVariableFromName(Name name) => getVariable(name.scope, name.value);
  FlowNode getFunction(FunctionNode node) => functions.putIfAbsent(node, () => new FlowNode()..function = node);
  FlowNode getCallee(CallExpression node) => callees.putIfAbsent(node, () => new FlowNode()..call = node);
  FlowNode getThis(FunctionNode node) => getVariable(node, '@this');
  FlowNode getReturn(FunctionNode node) => getVariable(node, '@return');
  
  void addEdge(FlowNode from, FlowNode to) {
    if (from == null || to == null) return;
    from.flowTo(to);
  }
  
  List<FunctionNode> findCallTargets(CallExpression call) {
    List<FunctionNode> result = <FunctionNode>[];
    Set<FlowNode> seen = new Set<FlowNode>();
    void search(FlowNode node) {
      if (!seen.add(node)) return;
      if (node.function != null) {
        result.add(node.function);
      }
      node.predecessors.forEach(search);
    }
    search(getCallee(call));
    return result;
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
    graph.addEdge(visit(node.callee), graph.getCallee(node.callee));
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

