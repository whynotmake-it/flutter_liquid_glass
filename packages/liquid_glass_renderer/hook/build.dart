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

/// Validation variants of the same core, loaded only under
/// `LIQUID_GLASS_VALIDATE_MATTE_ORDER`.
///
/// They are compiled only when a build opts in through the
/// `validate_matte_order` hook user-define (see below). A published package
/// dependency never sees that define, so a consumer's build ships the shipped
/// shaders and nothing else.
const _validationRuntimeEffectShaders = [
  'liquid_glass_final_render_validate',
  'liquid_glass_final_render_material_validate',
  'liquid_glass_final_render_tint_validate',
];

/// Hook user-define that opts a build into the matte-order validator.
///
/// It is read from the pubspec of the workspace root that builds this package
/// (for this repo, `example/pubspec.yaml`), so it applies only to the example
/// app and the CI runs that build it. A consumer app that depends on the
/// published package does not define it, so the validation shaders and their
/// stamp bundle are not compiled and do not end up in the app bundle. The flag
/// is `LIQUID_GLASS_VALIDATE_MATTE_ORDER` on the Dart side.
const _validateMatteOrderDefine = 'validate_matte_order';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final withMatteOrderValidator =
        input.userDefines[_validateMatteOrderDefine] == true;
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
    if (withMatteOrderValidator) {
      // The validation-only vertex/stamp bundle. Its own manifest keeps the
      // serial stamp out of the production bundle, so a shipped geometry
      // shader bundle is byte-identical whether or not the validator exists.
      await buildShaderBundleJson(
        buildInput: input,
        buildOutput: output,
        manifestFileName: 'liquid_glass_renderer_validate.shaderbundle.json',
        includeDirectories: [
          input.packageRoot.resolve('lib/assets/shaders/gpu/'),
        ],
        glesLanguageVersion: 300,
        assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
      );
    }
    await _buildRuntimeEffects(
      input,
      output,
      extraShaders: withMatteOrderValidator
          ? _validationRuntimeEffectShaders
          : const [],
    );
  });
}

/// Compiles each shader in [_runtimeEffectShaders] and [extraShaders] to
/// `build/shaderbundles/<name>.iplr`, an Impeller runtime-effect library
/// covering every backend except SkSL.
Future<void> _buildRuntimeEffects(
  BuildInput input,
  BuildOutputBuilder output, {
  required List<String> extraShaders,
}) async {
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

  for (final name in [..._runtimeEffectShaders, ...extraShaders]) {
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
