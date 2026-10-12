import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:hooks/hooks.dart';

/// Runtime-effect shaders compiled to `.iplr` by this hook instead of being
/// listed under `flutter.shaders` in the pubspec.
///
/// `flutter.shaders` are compiled for every backend a target platform
/// supports, including SkSL. These shaders use sampling that SkSL cannot
/// express, which makes Impeller-capable builds print a warning and Skia-only
/// builds (such as `flutter build web`) fail outright. Compiling here bundles
/// the same `.iplr` output that `FragmentProgram.fromAsset` decodes on
/// Impeller, while Skia builds never attempt a SkSL compile.
const _runtimeEffectShaders = [
  'liquid_glass_final_render',
  'liquid_glass_final_render_material',
  'liquid_glass_final_render_tint',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'liquid_glass_renderer.shaderbundle.json',
      includeDirectories: [
        input.packageRoot.resolve('lib/assets/shaders/gpu/'),
      ],
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
    );
    await _buildRuntimeEffects(input, output);
  });
}

/// Compiles each shader in [_runtimeEffectShaders] to
/// `build/shaderbundles/<name>.iplr`, an Impeller runtime-effect library
/// covering every backend except SkSL.
Future<void> _buildRuntimeEffects(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  final packageRoot = input.packageRoot;
  final shadersDirectory = packageRoot.resolve('lib/assets/shaders/');
  final outputDirectory = Directory.fromUri(
    packageRoot.resolve('build/shaderbundles/'),
  );
  await outputDirectory.create(recursive: true);

  final impellercExec = await findImpellerC();
  final help = Process.runSync(impellercExec.toFilePath(), ['--help']);
  final supportsDepfile =
      help.exitCode == 0 && impellerCHelpSupportsDepfile(help.stdout as String);
  final shaderLibDirectory = impellercExec.resolve('./shader_lib');

  for (final name in _runtimeEffectShaders) {
    final source = shadersDirectory.resolve('$name.frag');
    final outFile = outputDirectory.uri.resolve('$name.iplr');
    final spirv = File('${outFile.toFilePath()}.spirv');
    final depfile = File('${outFile.toFilePath()}.d');

    final result = Process.runSync(impellercExec.toFilePath(), [
      '--runtime-stage-metal',
      '--runtime-stage-gles',
      '--runtime-stage-gles3',
      '--runtime-stage-vulkan',
      '--iplr',
      '--input=${source.toFilePath()}',
      '--input-type=frag',
      '--sl=${outFile.toFilePath()}',
      '--spirv=${spirv.path}',
      '--include=${shadersDirectory.toFilePath()}',
      '--include=${shaderLibDirectory.toFilePath()}',
      if (supportsDepfile) '--depfile=${depfile.path}',
    ], workingDirectory: packageRoot.toFilePath());
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to compile runtime-effect shader "$name": '
        '${result.stderr}\n${result.stdout}',
      );
    }

    output.dependencies.add(source);
    if (depfile.existsSync()) {
      output.dependencies.addAll(
        parseImpellerCDepfileDependencies(
          depfile.readAsStringSync(),
          relativeTo: packageRoot,
        ),
      );
      depfile.deleteSync();
    }
    spirv.deleteSync();
  }

  // `impellerc` ships in lockstep with the engine, so the produced files are
  // only valid for the SDK that compiled them. Declaring the compiler (and a
  // stamp of it) as a dependency reruns this hook when a different SDK rewrote
  // the shared `build/` output.
  output.dependencies.add(impellercExec);
  final stampUri = outputDirectory.uri.resolve(
    'runtime_effects.engine_stamp.json',
  );
  await writeEngineStampIfChanged(
    stampUri: stampUri,
    impellercExec: impellercExec,
  );
  output.dependencies.add(stampUri);
}
