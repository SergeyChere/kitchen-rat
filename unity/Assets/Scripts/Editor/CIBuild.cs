using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace KitchenRat.EditorTools
{
    /// <summary>
    /// Entry point for the GitHub Actions build (GameCI unity-builder, buildMethod: KitchenRat.EditorTools.CIBuild.Build).
    /// The scenes are not in the repository: they are built from the models and night data first, then the player.
    /// </summary>
    public static class CIBuild
    {
        public static void Build()
        {
            string path = Arg("-customBuildPath") ?? "Build/KitchenRat";
            var target = EditorUserBuildSettings.activeBuildTarget;
            Debug.Log("Kitchen Rat CI: building scenes, then " + target + " → " + path);

            KitchenBuilder.BuildAll();
            AssetDatabase.SaveAssets();

            PlayerSettings.companyName = "SergeyChere";
            PlayerSettings.productName = "Kitchen Rat";
            var scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray();
            if (scenes.Length == 0) throw new Exception("Kitchen Rat CI: no scenes were built");

            string dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = path,
                target = target,
                options = BuildOptions.None,
            });
            Debug.Log("Kitchen Rat CI: " + report.summary.result + ", " + report.summary.totalErrors + " errors, " + (report.summary.totalSize / 1048576) + " MB");
            if (report.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        static string Arg(string name)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, name);
            return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
        }
    }
}
