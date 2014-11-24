import 'flowgraph.dart';
import 'dart:io';
import 'dart:convert';

void addNatives(FlowGraph graph) {
  Map json = JSON.decode(new File('natives.json').readAsStringSync());
  for (String nativeName in json.keys) {
    String fieldName = json[nativeName];
    graph.getField(fieldName).natives.add(nativeName);
  }
}

