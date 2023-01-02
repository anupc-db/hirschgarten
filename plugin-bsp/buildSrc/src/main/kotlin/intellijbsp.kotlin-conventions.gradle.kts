import io.gitlab.arturbosch.detekt.Detekt
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

plugins {
  // Kotlin
  kotlin("jvm")
  // detekt linter - read more: https://detekt.github.io/detekt/gradle.html
  id("io.gitlab.arturbosch.detekt")
  // ktlint linter - read more: https://github.com/JLLeitschuh/ktlint-gradle
  id("org.jlleitschuh.gradle.ktlint")
}

// Configure project's dependencies
repositories {
  mavenCentral()
}

kotlin {
  explicitApi()
}

// Configure detekt plugin.
// Read more: https://detekt.github.io/detekt/kotlindsl.html
detekt {
  autoCorrect = true
  ignoreFailures = false
  buildUponDefaultConfig = true
  config = files("$rootDir/detekt.yml")
  parallel = true
}

dependencies {

  implementation(libs.findLibrary("kotlinGradle").get())
  detektPlugins(libs.findLibrary("detektFormatting").get())
  implementation(kotlin("stdlib-jdk8"))
  implementation(kotlin("reflect"))
}

tasks {
  // Set the JVM compatibility versions
  javaVersion.let {
    withType<JavaCompile> {
      sourceCompatibility = it
      targetCompatibility = it
    }
    withType<KotlinCompile> {
      kotlinOptions.jvmTarget = it
    }
    withType<Detekt> {
      jvmTarget = it
    }
  }

  kotlinVersion.let {
    withType<KotlinCompile> {
      kotlinOptions.languageVersion = it
      kotlinOptions.apiVersion = it
    }
  }

  test {
    useJUnitPlatform()
    testLogging {
      events("PASSED", "SKIPPED", "FAILED")
    }
  }
}
