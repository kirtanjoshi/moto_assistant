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
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(android)
                if (currentNamespace == null) {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    var pkg: String? = null
                    if (manifestFile.exists()) {
                        val match = Regex("""package\s*=\s*"([^"]+)"""").find(manifestFile.readText())
                        pkg = match?.groupValues?.get(1)
                    }
                    if (pkg.isNullOrEmpty()) {
                        pkg = "com.legacy.${name.replace("-", "_")}"
                    }
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, pkg)
                }
            } catch (_: Exception) {}
        }
    }
}
