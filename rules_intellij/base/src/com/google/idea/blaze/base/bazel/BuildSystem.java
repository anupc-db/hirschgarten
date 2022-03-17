/*
 * Copyright 2022 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.google.idea.blaze.base.bazel;

import com.google.errorprone.annotations.MustBeClosed;
import com.google.idea.blaze.base.command.BlazeCommandRunner;
import com.google.idea.blaze.base.command.buildresult.BuildResultHelper;
import com.google.idea.blaze.base.command.info.BlazeInfo;
import com.google.idea.blaze.base.settings.BuildBinaryType;
import com.google.idea.blaze.base.settings.BuildSystemName;
import com.intellij.openapi.project.Project;
import java.util.Optional;

/**
 * Encapsulates interactions with a Bazel based build system.
 *
 * <p>The main purpose of this class is to provide instances of {@link BuildInvoker} to encapsulate
 * a method of executing Bazel commands.
 */
public interface BuildSystem {

  /** Encapsulates a means of executing build commands, often as a Bazel compatible binary. */
  interface BuildInvoker {

    /** Returns the type of this build interface. Used for logging purposes. */
    BuildBinaryType getType();

    /**
     * The path to the build binary on disk.
     *
     * <p>TODO(mathewi) This should really be fully encapsulated inside the runner returned from
     * {@link #getCommandRunner()} since it's not applicable to all implementations.
     */
    String getBinaryPath();

    /** Indicates if multiple invocations can be made at once. */
    boolean supportsParallelism();

    /**
     * Create a {@link BuildResultHelper} instance. This instance must be closed when it is finished
     * with.
     */
    @MustBeClosed
    BuildResultHelper createBuildResultProvider();

    /** Returns a {@link BlazeCommandRunner} to be used to invoke the build. */
    BlazeCommandRunner getCommandRunner();
  }

  /** Returns the type of the build system. */
  BuildSystemName getName();

  /** Get a Blaze invoker. */
  BuildInvoker getBuildInvoker(Project project);

  /**
   * Get a Blaze invoker that supports multiple calls in parallel, if this build system supports it.
   *
   * <p>TODO(mathewi) BlazeInfo should be fully encapsulated inside this interface so that callers
   * are not required to pass it in like this.
   *
   * @return An invoker, or {@code Optional.EMPTY} if parallelism is not supported.
   */
  Optional<BuildInvoker> getParallelBuildInvoker(Project project, BlazeInfo blazeInfo);
}
