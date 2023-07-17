"""Aspects to build and collect project dependencies."""

ALWAYS_BUILD_RULES = "java_proto_library,java_lite_proto_library,java_mutable_proto_library,kt_proto_library_helper"

def _package_dependencies_impl(target, ctx):
    file_name = target.label.name + ".target-info.txt"
    artifact_info_file = ctx.actions.declare_file(file_name)
    ctx.actions.write(
        artifact_info_file,
        _encode_target_info_proto(target),
    )

    return [OutputGroupInfo(
        qsync_jars = target[DependenciesInfo].compile_time_jars.to_list(),
        artifact_info_file = [artifact_info_file],
        qsync_aars = target[DependenciesInfo].aars.to_list(),
        qsync_gensrcs = target[DependenciesInfo].gensrcs.to_list(),
    )]

DependenciesInfo = provider(
    "The out-of-project dependencies",
    fields = {
        "compile_time_jars": "a list of jars generated by targets",
        "target_to_artifacts": "a map between a target and all its artifacts",
        "aars": "a list of aars with resource files",
        "gensrcs": "a list of sources generated by project targets",
        "test_mode_own_files": "a structure describing artifacts required when the target is requested within the project scope",
    },
)

def _encode_target_info_proto(target):
    contents = []
    for label, target_info in target[DependenciesInfo].target_to_artifacts.items():
        contents.append(
            struct(
                target = label,
                jars = target_info["jars"],
                ide_aars = target_info["ide_aars"],
                gen_srcs = target_info["gen_srcs"],
                srcs = target_info["srcs"],
            ),
        )
    return proto.encode_text(struct(artifacts = contents))

package_dependencies = aspect(
    implementation = _package_dependencies_impl,
    required_aspect_providers = [[DependenciesInfo]],
)

def generates_idl_jar(target):
    if AndroidIdeInfo not in target:
        return False
    return target[AndroidIdeInfo].idl_class_jar != None

def declares_android_resources(target, ctx):
    """
    Returns true if the target has resource files and an android provider.

    The IDE needs aars from targets that declare resources. AndroidIdeInfo
    has a defined_android_resources flag, but this returns true for additional
    cases (aidl files, etc), so we check if the target has resource files.

    Args:
      target: the target.
      ctx: the context.
    Returns:
      True if the target has resource files and an android provider.
    """
    if AndroidIdeInfo not in target:
        return False
    return hasattr(ctx.rule.attr, "resource_files") and len(ctx.rule.attr.resource_files) > 0

def declares_aar_import(ctx):
    """
    Returns true if the target has aar and is aar_import rule.

    Args:
      ctx: the context.
    Returns:
      True if the target has aar and is aar_import rule.
    """
    return ctx.rule.kind == "aar_import" and hasattr(ctx.rule.attr, "aar")

def _collect_dependencies_impl(target, ctx):
    return _collect_dependencies_core_impl(
        target,
        ctx,
        ctx.attr.include,
        ctx.attr.exclude,
        ctx.attr.always_build_rules,
        ctx.attr.generate_aidl_classes,
        test_mode = False,
    )

def _collect_all_dependencies_for_tests_impl(target, ctx):
    return _collect_dependencies_core_impl(
        target,
        ctx,
        include = None,
        exclude = None,
        always_build_rules = ALWAYS_BUILD_RULES,
        generate_aidl_classes = None,
        test_mode = True,
    )

def _target_within_project_scope(label, include, exclude):
    result = False
    if include:
        for inc in include.split(","):
            if label.startswith(inc):
                if label[len(inc)] in [":", "/"]:
                    result = True
                    break
    if result and len(exclude) > 0:
        for exc in exclude.split(","):
            if label.startswith(exc):
                if label[len(exc)] in [":", "/"]:
                    result = False
                    break
    return result

def _get_followed_dependency_infos(rule):
    deps = []
    if hasattr(rule.attr, "deps"):
        deps += rule.attr.deps
    if hasattr(rule.attr, "exports"):
        deps += rule.attr.exports
    if hasattr(rule.attr, "_junit"):
        deps.append(rule.attr._junit)

    return [
        dep[DependenciesInfo]
        for dep in deps
        if DependenciesInfo in dep and dep[DependenciesInfo].target_to_artifacts
    ]

def _collect_own_artifacts(
        target,
        ctx,
        dependency_infos,
        always_build_rules,
        generate_aidl_classes,
        target_is_within_project_scope):
    rule = ctx.rule
    can_follow_dependencies = bool(dependency_infos)

    must_build_main_artifacts = (
        not target_is_within_project_scope or rule.kind in always_build_rules.split(",")
    )

    own_jar_files = []
    own_jar_depsets = []
    own_ide_aar_files = []
    own_gensrc_files = []
    own_src_files = []

    if must_build_main_artifacts:
        # For rules that we do not follow dependencies of (either because they don't
        # have further dependencies with JavaInfo or do so in attributes we don't care)
        # we gather all their transitive dependencies. If they have dependencies, we
        # only gather their own compile jars and continue down the tree.
        # This is done primarily for rules like proto, where they don't have dependencies
        # and add their "toolchain" classes to transitive deps.
        if can_follow_dependencies:
            own_jar_depsets.append(target[JavaInfo].compile_jars)
        else:
            own_jar_depsets.append(target[JavaInfo].transitive_compile_time_jars)

        if declares_android_resources(target, ctx):
            ide_aar = _get_ide_aar_file(target, ctx)
            if ide_aar:
                own_ide_aar_files.append(ide_aar)
        elif declares_aar_import(ctx):
            own_ide_aar_files.append(rule.attr.aar.files.to_list()[0])

    else:
        if generate_aidl_classes and generates_idl_jar(target):
            idl_jar = target[AndroidIdeInfo].idl_class_jar
            own_jar_files.append(idl_jar)

            # An AIDL base jar needed for resolving base classes for aidl generated stubs,
            if hasattr(rule.attr, "_android_sdk"):
                android_sdk_info = getattr(rule.attr, "_android_sdk")[AndroidSdkInfo]
                own_jar_depsets.append(android_sdk_info.aidl_lib.files)

        # Add generated java_outputs (e.g. from annotation processing
        generated_class_jars = []
        for java_output in target[JavaInfo].java_outputs:
            if java_output.generated_class_jar:
                generated_class_jars.append(java_output.generated_class_jar)
        if generated_class_jars:
            own_jar_files += generated_class_jars

        # Add generated sources for included targets
        if hasattr(rule.attr, "srcs"):
            for src in rule.attr.srcs:
                for file in src.files.to_list():
                    if not file.is_source:
                        own_gensrc_files.append(file)

    if not target_is_within_project_scope and hasattr(rule.attr, "srcs"):
        own_src_files = rule.attr.srcs

    return (
        own_jar_files,
        own_jar_depsets,
        own_ide_aar_files,
        own_gensrc_files,
        own_src_files,
    )

def _collect_own_and_dependency_artifacts(
        target,
        ctx,
        dependency_infos,
        always_build_rules,
        generate_aidl_classes,
        target_is_within_project_scope):
    own_jar_files, own_jar_depsets, own_ide_aar_files, own_gensrc_files, own_src_files = _collect_own_artifacts(
        target,
        ctx,
        dependency_infos,
        always_build_rules,
        generate_aidl_classes,
        target_is_within_project_scope,
    )

    has_own_artifacts = (
        len(own_jar_files) + len(own_jar_depsets) + len(own_ide_aar_files) + len(own_gensrc_files) + len(own_src_files)
    ) > 0

    target_to_artifacts = {}
    if has_own_artifacts:
        jars = depset(own_jar_files, transitive = own_jar_depsets).to_list()

        # Pass the following lists through depset() too to remove any duplicates.
        ide_aars = depset(own_ide_aar_files).to_list()
        gen_srcs = depset(own_gensrc_files).to_list()
        target_to_artifacts[str(target.label)] = {
            "jars": [_output_relative_path(file.path) for file in jars],
            "ide_aars": [_output_relative_path(file.path) for file in ide_aars],
            "gen_srcs": [_output_relative_path(file.path) for file in gen_srcs],
            "srcs": [file.path for target in own_src_files for file in target.files.to_list()],
        }

    own_and_transitive_jar_depsets = list(own_jar_depsets)  # Copy to prevent changes to own_jar_depsets.
    own_and_transitive_ide_aar_depsets = []
    own_and_transitive_gensrc_depsets = []

    for info in dependency_infos:
        target_to_artifacts.update(info.target_to_artifacts)
        own_and_transitive_jar_depsets.append(info.compile_time_jars)
        own_and_transitive_ide_aar_depsets.append(info.aars)
        own_and_transitive_gensrc_depsets.append(info.gensrcs)

    return (
        target_to_artifacts,
        depset(own_jar_files, transitive = own_and_transitive_jar_depsets),
        depset(own_ide_aar_files, transitive = own_and_transitive_ide_aar_depsets),
        depset(own_gensrc_files, transitive = own_and_transitive_gensrc_depsets),
    )

def _collect_dependencies_core_impl(
        target,
        ctx,
        include,
        exclude,
        always_build_rules,
        generate_aidl_classes,
        test_mode):
    if JavaInfo not in target:
        return [DependenciesInfo(
            compile_time_jars = depset(),
            target_to_artifacts = {},
            aars = depset(),
            gensrcs = depset(),
            test_mode_own_files = None,
        )]

    target_is_within_project_scope = _target_within_project_scope(str(target.label), include, exclude) and not test_mode
    dependency_infos = _get_followed_dependency_infos(ctx.rule)

    target_to_artifacts, compile_jars, aars, gensrcs = _collect_own_and_dependency_artifacts(
        target,
        ctx,
        dependency_infos,
        always_build_rules,
        generate_aidl_classes,
        target_is_within_project_scope,
    )

    test_mode_own_files = None
    if test_mode:
        (
            within_scope_own_jar_files,
            within_scope_own_jar_depsets,
            within_scope_own_ide_aar_files,
            within_scope_own_gensrc_files,
            _,
        ) = _collect_own_artifacts(
            target,
            ctx,
            dependency_infos,
            always_build_rules,
            generate_aidl_classes,
            target_is_within_project_scope = True,
        )
        test_mode_own_files = struct(
            test_mode_within_scope_own_jar_files = depset(within_scope_own_jar_files, transitive = within_scope_own_jar_depsets).to_list(),
            test_mode_within_scope_own_ide_aar_files = within_scope_own_ide_aar_files,
            test_mode_within_scope_own_gensrc_files = within_scope_own_gensrc_files,
        )

    return [
        DependenciesInfo(
            target_to_artifacts = target_to_artifacts,
            compile_time_jars = compile_jars,
            aars = aars,
            gensrcs = gensrcs,
            test_mode_own_files = test_mode_own_files,
        ),
    ]

def _get_ide_aar_file(target, ctx):
    """
    Builds a resource only .aar file for the ide.

    The IDE requires just resource files and the manifest from the IDE.
    Moreover, there are cases when the existing rules fail to build a full .aar
    file from a library, on which other targets can still depend.

    The function builds a minimalistic .aar file that contains resources and the
    manifest only.
    """
    full_aar = target[AndroidIdeInfo].aar
    if full_aar:
        resource_files = _collect_resource_files(ctx)
        resource_map = _build_ide_aar_file_map(target[AndroidIdeInfo].manifest, resource_files)
        aar = ctx.actions.declare_file(full_aar.short_path.removesuffix(".aar") + "_ide/" + full_aar.basename)
        _package_ide_aar(ctx, aar, resource_map)
        return aar
    else:
        return None

def _collect_resource_files(ctx):
    """
    Collects the list of resource files from the target rule attributes.
    """

    # Unfortunately, there are no suitable bazel providers that describe
    # resource files used a target.
    # However, AndroidIdeInfo returns a reference to a so-called resource APK
    # file, which contains everything the IDE needs to load resources from a
    # given library. However, this format is currently supported by Android
    # Studio in the namespaced resource mode. We should consider conditionally
    # enabling support in Android Studio and use them in ASwB, instead of
    # building special .aar files for the IDE.
    resource_files = []
    for t in ctx.rule.attr.resource_files:
        for f in t.files.to_list():
            resource_files.append(f)
    return resource_files

def _build_ide_aar_file_map(manifest_file, resource_files):
    """
    Build the list of files and their paths as they have to appear in .aar.
    """
    file_map = {}
    file_map["AndroidManifest.xml"] = manifest_file
    for f in resource_files:
        res_dir_path = f.short_path \
            .removeprefix(android_common.resource_source_directory(f)) \
            .removeprefix("/")
        if res_dir_path:
            res_dir_path = "res/" + res_dir_path
            file_map[res_dir_path] = f
    return file_map

_CONTROL_FILE_ENTRY = '''entry {
  zip_path: "%s"
  exec_path: "%s"
}'''

def _package_ide_aar(ctx, aar, file_map):
    """
    Declares a file and defines actions to build .aar according to file_map.

    The IDE.aar file is produces by an aspect and therefore it cannot define
    additional targets and thus cannot use genzip() rule. This function reuses
    //tools/genzip:build_zip tool, which is used by getzip() rule.
    """
    actions = ctx.actions
    control_file = actions.declare_file(".control", sibling = aar)
    control_content = ['output_filename: "%s"' % aar.path]
    files = []
    for aar_dir_path, f in file_map.items():
        files.append(f)
        control_content.append(_CONTROL_FILE_ENTRY % (aar_dir_path, f.path))
    control_content.append("compression: STORED")
    actions.write(control_file, "\n".join(control_content))
    actions.run(
        mnemonic = "GenerateIdeAar",
        executable = ctx.executable._build_zip,
        inputs = files + [control_file],
        outputs = [aar],
        arguments = ["--control", control_file.path],
    )

def _output_relative_path(path):
    """Get file path relative to the output path.

    Args:
         path: path of artifact path = (../repo_name)? + (root_fragment)? + relative_path

    Returns:
         path relative to the output path
    """
    if (path.startswith("blaze-out/")) or (path.startswith("bazel-out/")):
        # len("blaze-out/") or len("bazel-out/")
        path = path[10:]
    return path

collect_dependencies = aspect(
    implementation = _collect_dependencies_impl,
    provides = [DependenciesInfo],
    attr_aspects = ["deps", "exports", "_junit"],
    attrs = {
        "include": attr.string(
            doc = "Comma separated list of workspace paths included in the project as source. Any targets inside here will not be built.",
            mandatory = True,
        ),
        "exclude": attr.string(
            doc = "Comma separated list of exclusions to 'include'.",
            default = "",
        ),
        "always_build_rules": attr.string(
            doc = "Comma separated list of rules. Any targets belonging to these rules will be built, regardless of location",
            default = "",
        ),
        "generate_aidl_classes": attr.bool(
            doc = "If True, generates classes for aidl files included as source for the project targets",
            default = False,
        ),
        "_build_zip": attr.label(
            allow_files = True,
            cfg = "exec",
            executable = True,
            default = "@//tools/genzip:build_zip",
        ),
    },
)

collect_all_dependencies_for_tests = aspect(
    doc = """
    A variant of collect_dependencies aspect used by query sync integration
    tests.

    The difference is that collect_all_dependencies does not apply
    include/exclude directory filtering, which is applied in the test framework
    instead. See: test_project.bzl for more details.
    """,
    implementation = _collect_all_dependencies_for_tests_impl,
    provides = [DependenciesInfo],
    attr_aspects = ["deps", "exports", "_junit"],
    attrs = {
        "_build_zip": attr.label(
            allow_files = True,
            cfg = "exec",
            executable = True,
            default = "@//tools/genzip:build_zip",
        ),
    },
)
