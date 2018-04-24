/*
 * Copyright 2018 The Bazel Authors. All rights reserved.
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
package com.google.idea.blaze.java.fastbuild;

import com.google.common.collect.ImmutableMap;
import java.util.Map;

/** An exception compiling code using the {@link FastBuildService}. */
public class FastBuildCompileException extends FastBuildException {

  private final ImmutableMap<String, String> loggingData;

  FastBuildCompileException(String message, Map<String, String> loggingData) {
    super(message);
    this.loggingData = ImmutableMap.copyOf(loggingData);
  }

  public ImmutableMap<String, String> getLoggingData() {
    return loggingData;
  }
}
