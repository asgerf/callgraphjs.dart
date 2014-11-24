callgraphjs
-----------

Approximate call graph construction for JavaScript, based on the algorithm in [this paper](http://cs.au.dk/~asf/icse13-callgraphs.pdf), using straightforward depth-first search as its transitive closure.

This implementation is intended for demonstration and reference purposes.

It also serves as an example of how to use [parsejs](https://github.com/asgerf/parsejs.dart).

Example usage
-------------

    git checkout https://github.com/asgerf/callgraphjs.dart
    cd callgraphjs.dart/bin
    dart main.dart ../benchmarks/deltablue.js
