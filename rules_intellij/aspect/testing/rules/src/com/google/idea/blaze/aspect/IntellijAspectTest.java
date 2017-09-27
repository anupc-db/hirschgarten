/*
 * Copyright 2017 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.google.idea.blaze.aspect;

import static java.util.stream.Collectors.toList;

import com.google.common.collect.ImmutableList;
import com.google.devtools.intellij.IntellijAspectTestFixtureOuterClass.IntellijAspectTestFixture;
import com.google.devtools.intellij.IntellijAspectTestFixtureOuterClass.OutputGroup;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.ArtifactLocation;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.Dependency;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.Dependency.DependencyType;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.LibraryArtifact;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.TargetIdeInfo;
import com.google.devtools.intellij.ideinfo.IntellijIdeInfo.TargetKey;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Set;

/** Abstract base class for Intellij aspect tests. */
public abstract class IntellijAspectTest {

  private final Path packagePath;

  protected IntellijAspectTest(String base) {
    this.packagePath =
        Paths.get(base, getClass().getPackage().getName().replace(".", File.separator));
  }

  public IntellijAspectTestFixture loadTestFixture(String testRelativeLabel) throws IOException {
    String label = testRelative(testRelativeLabel);
    String relativePath = label.replace(':', '/') + ".intellij-aspect-test-fixture";
    relativePath = relativePath.substring(2);
    File runfilesPath = runfilesPath(relativePath).toFile();
    try (InputStream inputStream = new FileInputStream(runfilesPath)) {
      return IntellijAspectTestFixture.parseFrom(inputStream);
    }
  }

  protected TargetIdeInfo findTarget(
      IntellijAspectTestFixture testFixture, String maybeRelativeLabel) {
    String label =
        maybeRelativeLabel.startsWith("//") ? maybeRelativeLabel : testRelative(maybeRelativeLabel);
    return testFixture
        .getTargetsList()
        .stream()
        .filter(target -> matchTarget(target, label))
        .findAny()
        .orElse(null);
  }

  protected TargetIdeInfo findAspectTarget(
      IntellijAspectTestFixture testFixture,
      String maybeRelativeLabel,
      String... fractionalAspectIds) {
    String label =
        maybeRelativeLabel.startsWith("//") ? maybeRelativeLabel : testRelative(maybeRelativeLabel);
    return testFixture
        .getTargetsList()
        .stream()
        .filter(target -> matchTarget(target, label, fractionalAspectIds))
        .findAny()
        .orElse(null);
  }

  protected static ImmutableList<String> getFilesForOutputGroups(
      IntellijAspectTestFixture testFixture, Set<String> groupNames) {
    ImmutableList.Builder<String> list = ImmutableList.builder();
    for (OutputGroup group : testFixture.getOutputGroupsList()) {
      if (groupNames.contains(group.getName())) {
        list.addAll(group.getFilePathsList());
      }
    }
    return list.build();
  }

  protected static List<String> getOutputGroupFiles(
      IntellijAspectTestFixture testFixture, String name) {
    for (OutputGroup group : testFixture.getOutputGroupsList()) {
      if (group.getName().equals(name)) {
        return group.getFilePathsList();
      }
    }
    return ImmutableList.of();
  }

  private static boolean matchTarget(TargetIdeInfo target, String label) {
    if (target.hasKey()) {
      TargetKey targetKey = target.getKey();
      return targetKey.getLabel().equals(label) && targetKey.getAspectIdsList().isEmpty();
    } else {
      return target.getLabel().equals(label);
    }
  }

  private static boolean matchTarget(
      TargetIdeInfo target, String label, String... fractionalAspectIds) {
    if (!target.hasKey()) {
      return false;
    }

    TargetKey targetKey = target.getKey();
    if (!targetKey.getLabel().equals(label)) {
      return false;
    }
    for (String fractionalAspectId : fractionalAspectIds) {
      if (targetKey
          .getAspectIdsList()
          .stream()
          .noneMatch(aspectId -> aspectId.contains(fractionalAspectId))) {
        return false;
      }
    }
    return true;
  }

  protected static List<Dependency> dependenciesForTarget(TargetIdeInfo target) {
    if (!target.getDepsList().isEmpty()) {
      return target.getDepsList();
    } else if (!target.getDependenciesList().isEmpty() || !target.getRuntimeDepsList().isEmpty()) {
      ImmutableList.Builder<Dependency> result = ImmutableList.builder();
      for (String label : target.getDependenciesList()) {
        result.add(
            Dependency.newBuilder()
                .setDependencyType(DependencyType.COMPILE_TIME)
                .setTarget(TargetKey.newBuilder().setLabel(label).build())
                .build());
      }
      for (String label : target.getRuntimeDepsList()) {
        result.add(
            Dependency.newBuilder()
                .setDependencyType(DependencyType.RUNTIME)
                .setTarget(TargetKey.newBuilder().setLabel(label).build())
                .build());
      }
      return result.build();
    }
    return ImmutableList.of();
  }

  protected String testRelative(String path) {
    String relativePath =
        path.startsWith(":")
            ? packagePath.toString() + path
            : Paths.get(packagePath.toString(), path).toString();
    return path.contains(":") ? "//" + relativePath : relativePath;
  }

  protected Dependency dep(String maybeRelativeLabel) {
    return dep(maybeRelativeLabel, DependencyType.COMPILE_TIME);
  }

  protected Dependency runtimeDep(String maybeRelativeLabel) {
    return dep(maybeRelativeLabel, DependencyType.RUNTIME);
  }

  private Dependency dep(String maybeRelativeLabel, DependencyType dependencyType) {
    String label =
        maybeRelativeLabel.startsWith("//") ? maybeRelativeLabel : testRelative(maybeRelativeLabel);
    return Dependency.newBuilder()
        .setDependencyType(dependencyType)
        .setTarget(TargetKey.newBuilder().setLabel(label))
        .build();
  }

  protected Dependency dep(TargetIdeInfo targetIdeInfo) {
    TargetKey targetKey =
        targetIdeInfo.hasKey()
            ? targetIdeInfo.getKey()
            : TargetKey.newBuilder().setLabel(targetIdeInfo.getLabel()).build();
    return Dependency.newBuilder()
        .setDependencyType(DependencyType.COMPILE_TIME)
        .setTarget(targetKey)
        .build();
  }

  protected static String libraryArtifactToString(LibraryArtifact libraryArtifact) {
    StringBuilder stringBuilder = new StringBuilder();
    if (libraryArtifact.hasJar()) {
      stringBuilder.append("<jar:");
      stringBuilder.append(libraryArtifact.getJar().getRelativePath());
      stringBuilder.append(">");
    }
    if (libraryArtifact.hasInterfaceJar()) {
      stringBuilder.append("<ijar:");
      stringBuilder.append(libraryArtifact.getInterfaceJar().getRelativePath());
      stringBuilder.append(">");
    }
    if (libraryArtifact.hasSourceJar()) {
      stringBuilder.append("<source:");
      stringBuilder.append(libraryArtifact.getSourceJar().getRelativePath());
      stringBuilder.append(">");
    }

    return stringBuilder.toString();
  }

  /** Constructs a string that matches OutputJar#toString for comparison testing. */
  protected static String jarString(String jar, String iJar, String sourceJar) {
    StringBuilder sb = new StringBuilder();
    if (jar != null) {
      sb.append("<jar:" + jar + ">");
    }
    if (iJar != null) {
      sb.append("<ijar:" + iJar + ">");
    }
    if (sourceJar != null) {
      sb.append("<source:" + sourceJar + ">");
    }
    return sb.toString();
  }

  protected static Iterable<String> relativePathsForArtifacts(List<ArtifactLocation> sourcesList) {
    return sourcesList.stream().map(ArtifactLocation::getRelativePath).collect(toList());
  }

  /** Returns the runtime location of a data dependency. */
  private static Path runfilesPath(String relativePath) {
    return Paths.get(getUserValue("TEST_SRCDIR"), getUserValue("TEST_WORKSPACE"), relativePath);
  }

  /**
   * Returns the value for system property <code>name</code>, or if that is not found the value of
   * the user's environment variable <code>name</code>. If neither is found, null is returned.
   *
   * @param name the name of property to get
   * @return the value of the property or null if it is not found
   */
  private static String getUserValue(String name) {
    String propValue = System.getProperty(name);
    if (propValue == null) {
      return System.getenv(name);
    }
    return propValue;
  }
}
