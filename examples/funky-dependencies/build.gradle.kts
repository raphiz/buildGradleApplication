import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "2.1.0"
    application
}

application {
    mainClass.set("MainKt")
}

group = "org.example"
version = System.getenv("APP_VERSION") ?: "dirty"

dependencies {
    implementation(kotlin("stdlib-jdk8"))

    // Dependency with artifact that does not follow the maven default convention
    // https://github.com/raphiz/buildGradleApplication/issues/30
    implementation("com.github.ajalt.clikt:clikt:5.0.1")
    
    // implicitly requires kotlinx-serialization-core-metadata-x.y.z.jar which has multiple gradle variants (and hence URLs)
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-jvm:1.7.3")

    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}

val javaVersion = JavaLanguageVersion.of("21")

java {
    toolchain {
        languageVersion.set(javaVersion)
    }
}

tasks.withType<KotlinCompile> {
    compilerOptions {
        freeCompilerArgs.set(listOf("-Xjsr305=strict"))
        jvmTarget.set(JvmTarget.fromTarget(javaVersion.toString()))
    }
}


tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}

configurations.all {
    resolutionStrategy {
        failOnNonReproducibleResolution()
    }
}