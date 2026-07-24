allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Some plugins (e.g. printing) pull androidx that needs compileSdk >= 31
    // (android:attr/lStar). Force a modern compileSdk on every Android module.
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
