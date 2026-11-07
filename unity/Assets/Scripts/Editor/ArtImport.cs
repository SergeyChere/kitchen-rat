using System.Collections.Generic;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEngine;

namespace KitchenRat.EditorTools
{
    /// <summary>
    /// Import settings for everything in Assets/Art (the FBX files made by tools/blender):
    /// characters get a Generic rig and named looping clips, other models no animation;
    /// materials switch to the toon shader with the exact colour from the Blender material name (c rrggbb).
    /// </summary>
    public class ArtImport : AssetPostprocessor
    {
        const string Root = "Assets/Art/";
        static readonly HashSet<string> OneShot = new HashSet<string>
        {
            "jump_up", "jump_down", "land", "wake_up", "pounce", "swat", "place_trap", "toss",
            "sit_up_scream", "sit_up", "yawn", "drink", "head_up", "meow", "bark", "squeak",
            "stand_up", "react_scared", "set_trap", "crouch_look",
        };
        static readonly Regex HexName = new Regex("^c([0-9a-fA-F]{6})");

        bool Ours => assetPath.StartsWith(Root);
        bool IsCharacter => assetPath.StartsWith(Root + "characters/");

        void OnPreprocessModel()
        {
            if (!Ours) return;
            var mi = (ModelImporter)assetImporter;
            mi.bakeAxisConversion = true;
            mi.importCameras = false;
            mi.importLights = false;
            mi.importBlendShapes = false;
            mi.materialImportMode = ModelImporterMaterialImportMode.ImportViaMaterialDescription;
            mi.animationType = IsCharacter ? ModelImporterAnimationType.Generic : ModelImporterAnimationType.None;
            mi.importAnimation = IsCharacter;
        }

        void OnPreprocessAnimation()
        {
            if (!Ours || !IsCharacter) return;
            var mi = (ModelImporter)assetImporter;
            var clips = mi.defaultClipAnimations;
            foreach (var c in clips)
            {
                c.name = KitchenRat.ClipPlayer.Short(c.name);
                c.loopTime = !OneShot.Contains(c.name);
            }
            mi.clipAnimations = clips;
        }

        void OnPostprocessMaterial(Material m)
        {
            if (!Ours) return;
            var toon = Shader.Find("KitchenRat/Toon");
            if (!toon) return; // first import before the shader exists: run "Kitchen Rat/Reimport Art"
            Color col = m.HasProperty("_Color") ? m.GetColor("_Color") : Color.white;
            var hex = HexName.Match(m.name);
            if (hex.Success && ColorUtility.TryParseHtmlString("#" + hex.Groups[1].Value, out var exact)) col = new Color(exact.r, exact.g, exact.b, col.a);
            if (col.a < 0.99f)
            {
                m.SetColor("_Color", col); // glass, water: keep the transparent Standard material
                return;
            }
            Color emit = m.HasProperty("_EmissionColor") && m.IsKeywordEnabled("_EMISSION") ? m.GetColor("_EmissionColor") : Color.black;
            if (emit.maxColorComponent > 0.01f) emit = col * 1.5f;
            m.shader = toon;
            m.SetColor("_Color", col);
            m.SetColor("_EmissionColor", emit);
        }
    }
}
