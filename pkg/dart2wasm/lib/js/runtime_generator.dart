// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_js_interop_checks/src/js_interop.dart'
    show calculateTransitiveImportsOfJsInteropIfUsed;
import 'package:_js_interop_checks/src/transformations/static_interop_class_eraser.dart';
import 'package:dart2wasm/js/interop_transformer.dart';
import 'package:dart2wasm/js/method_collector.dart';
import 'package:dart2wasm/js/runtime_blob.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';

JSMethods _performJSInteropTransformations(
    Component component,
    CoreTypes coreTypes,
    ClassHierarchy classHierarchy,
    Set<Library> interopDependentLibraries) {
  // Transform kernel and generate JS methods.
  final transformer = InteropTransformer(coreTypes, classHierarchy);
  for (final library in interopDependentLibraries) {
    transformer.visitLibrary(library);
  }

  // We want static types to help us specialize methods based on receivers.
  // Therefore, erasure must come after the lowering.
  final staticInteropClassEraser = StaticInteropClassEraser(coreTypes, null,
      libraryForJavaScriptObject: 'dart:_js_helper',
      classNameOfJavaScriptObject: 'JSValue',
      additionalCoreLibraries: {'_js_helper', '_js_types', 'js_interop'});
  for (Library library in interopDependentLibraries) {
    staticInteropClassEraser.visitLibrary(library);
  }
  return transformer.jsMethods;
}

class RuntimeFinalizer {
  final Map<Procedure, String> allJSMethods;

  RuntimeFinalizer(this.allJSMethods);

  String generate(Iterable<Procedure> translatedProcedures) {
    Set<Procedure> usedProcedures = {};
    List<String> usedJSMethods = [];
    for (Procedure p in translatedProcedures) {
      if (usedProcedures.add(p) && allJSMethods.containsKey(p)) {
        usedJSMethods.add(allJSMethods[p]!);
      }
    }
    return '''
  $jsRuntimeBlobPart1
  ${usedJSMethods.join(',\n')}
  $jsRuntimeBlobPart2
''';
  }
}

RuntimeFinalizer createRuntimeFinalizer(
    Component component, CoreTypes coreTypes, ClassHierarchy classHierarchy) {
  Set<Library> transitiveImportingJSInterop = {
    ...?calculateTransitiveImportsOfJsInteropIfUsed(
        component, Uri.parse("package:js/js.dart")),
    ...?calculateTransitiveImportsOfJsInteropIfUsed(
        component, Uri.parse("dart:_js_annotations")),
    ...?calculateTransitiveImportsOfJsInteropIfUsed(
        component, Uri.parse("dart:_js_helper")),
  };
  Map<Procedure, String> jsInteropMethods = {};
  jsInteropMethods = _performJSInteropTransformations(
      component, coreTypes, classHierarchy, transitiveImportingJSInterop);
  return RuntimeFinalizer(jsInteropMethods);
}
