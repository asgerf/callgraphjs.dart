import 'jscallgraphs.dart';
import 'package:parsejs/parsejs.dart';
import 'dart:io';

void main(List<String> args) {
  String filename = args[0];
  new File(filename).readAsString().then((String code) {
    Program ast = parsejs(code, filename: filename);
    FlowGraph flowGraph = buildFlowGraph(ast);
    
    findCalls(Node node) {
      if (node is CallExpression) {
        List<FunctionNode> targets = flowGraph.findCallTargets(node);
        print("${node.location}: ${targets}");
      }
      node.forEach(findCalls);
    }
    
    findCalls(ast);
  });
}

