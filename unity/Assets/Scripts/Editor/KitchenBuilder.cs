using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace KitchenRat.EditorTools
{
    /// <summary>
    /// Builds a scene for every night that uses the kitchen layout (nights 1, 5, 6, 14, 16) from the generated models and
    /// the night data in Resources/Nights (exported from game/js/levels.js). Runs by itself the first time the project opens;
    /// rebuild with Kitchen Rat → Build Kitchen Nights. Positions use the prototype's room coordinates in cm.
    /// </summary>
    public static class KitchenBuilder
    {
        public const string Art = "Assets/Art/";
        public const string SceneDir = "Assets/Scenes";
        const string MatDir = "Assets/Materials";
        public static readonly string[] KitchenNights = { "kitchen", "kitchen2", "water", "party", "vacuum" };
        public static string FirstScene => SceneDir + "/01_kitchen.unity";

        static float unit = 1f;
        static Transform root, furnRoot, decorRoot, foodRoot;
        static Night night;

        [MenuItem("Kitchen Rat/Build Kitchen Nights", priority = 1)]
        public static void BuildMenu()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            BuildAll();
            EditorSceneManager.OpenScene(FirstScene);
        }

        [MenuItem("Kitchen Rat/Reimport Art", priority = 20)]
        public static void ReimportArt()
        {
            AssetDatabase.ImportAsset("Assets/Art", ImportAssetOptions.ImportRecursive | ImportAssetOptions.ForceUpdate);
        }

        static Vector3 W(float x, float y, float h = 0f) => Nights.World(x, y, h);

        public static void BuildAll()
        {
            if (!ArtUsesToon()) ReimportArt();
            var scenes = new List<EditorBuildSettingsScene>();
            foreach (var id in KitchenNights)
            {
                var n = Nights.Load(id);
                string path = SceneDir + "/" + n.number.ToString("00") + "_" + n.id + ".unity";
                Build(n, path);
                scenes.Add(new EditorBuildSettingsScene(path, true));
            }
            EditorBuildSettings.scenes = scenes.ToArray();
            if (File.Exists(SceneDir + "/Kitchen.unity")) AssetDatabase.DeleteAsset(SceneDir + "/Kitchen.unity"); // the first skeleton's scene
            Debug.Log("Kitchen Rat: built " + scenes.Count + " kitchen nights" + (unit != 1f ? " (model scale corrected ×" + unit + ")" : ""));
        }

        public static void Build(Night n, string path)
        {
            night = n;
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            unit = MeasureUnit();
            root = new GameObject("Night " + n.number + " · " + n.name).transform;
            furnRoot = Group("Furniture");
            decorRoot = Group("Decor");
            foodRoot = Group("Food");

            var roomLight = Lighting();
            Room();
            Furniture();
            Physics.SyncTransforms();
            Decor();
            NestRoom();
            Physics.SyncTransforms();
            Knockables();
            Food();
            Traps();
            var rat = Rat();
            var cam = MakeCamera(rat);
            rat.cameraRig = cam.transform;
            var cat = Cat();
            var owner = Owner(roomLight);
            Game(rat, cam.GetComponent<FollowCamera>(), cat, owner);

            Directory.CreateDirectory(SceneDir);
            EditorSceneManager.SaveScene(scene, path);
        }

        // ---------- helpers ----------

        static Transform Group(string name)
        {
            var t = new GameObject(name).transform;
            t.SetParent(root, false);
            return t;
        }

        static GameObject Load(string path) => AssetDatabase.LoadAssetAtPath<GameObject>(Art + path + ".fbx");

        static bool ArtUsesToon()
        {
            var m = AssetDatabase.LoadAllAssetsAtPath(Art + "furniture/fridge.fbx").OfType<Material>().FirstOrDefault();
            return m == null || m.shader.name == "KitchenRat/Toon" || Shader.Find("KitchenRat/Toon") == null;
        }

        static float MeasureUnit()
        {
            var src = Load("furniture/fridge");
            if (!src) return 1f;
            var go = Object.Instantiate(src);
            float h = BoundsOf(go).size.y;
            Object.DestroyImmediate(go);
            return h > 0.01f && Mathf.Abs(h - 1.85f) > 0.3f ? 1.85f / h : 1f;
        }

        static Bounds BoundsOf(GameObject go)
        {
            var rs = go.GetComponentsInChildren<Renderer>();
            if (rs.Length == 0) return new Bounds(go.transform.position, Vector3.zero);
            var b = rs[0].bounds;
            foreach (var r in rs) b.Encapsulate(r.bounds);
            return b;
        }

        static GameObject Spawn(string path, Vector3 pos, float rotY = 0f, Transform parent = null)
        {
            var src = Load(path);
            if (!src)
            {
                Debug.LogWarning("Kitchen Rat: missing model " + path);
                return null;
            }
            var go = (GameObject)PrefabUtility.InstantiatePrefab(src, parent ? parent : root);
            go.transform.localScale = go.transform.localScale * unit;
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, rotY, 0f));
            return go;
        }

        /// <summary>Scale to a footprint (cm) along the model's own X (width) and Z (depth); h scales the height. 0 keeps a size.</summary>
        static void Fit(GameObject go, float w, float d, float h = 0f)
        {
            if (!go) return;
            var rot = go.transform.rotation;
            go.transform.rotation = Quaternion.identity;
            var b = BoundsOf(go);
            var s = go.transform.localScale;
            if (w > 0f && b.size.x > 1e-4f) s.x *= w / 100f / b.size.x;
            if (d > 0f && b.size.z > 1e-4f) s.z *= d / 100f / b.size.z;
            if (h > 0f && b.size.y > 1e-4f) s.y *= h / 100f / b.size.y;
            go.transform.localScale = s;
            go.transform.rotation = rot;
        }

        static void Collide(GameObject go)
        {
            if (!go) return;
            foreach (var mf in go.GetComponentsInChildren<MeshFilter>())
                if (!mf.GetComponent<Collider>()) mf.gameObject.AddComponent<MeshCollider>().sharedMesh = mf.sharedMesh;
        }

        static GameObject Furn(string path, float x, float y, float rotY, string surface, float w = 0f, float d = 0f, float h = 0f)
        {
            var go = Spawn(path, W(x, y), rotY, furnRoot);
            if (!go) return null;
            Fit(go, w, d, h);
            Collide(go);
            if (surface != null) go.AddComponent<Surface>().id = surface;
            return go;
        }

        /// <summary>The top of whatever is at (x, y): floor, counter, table…</summary>
        static Vector3 OnTop(float x, float y)
        {
            var o = W(x, y, 240f);
            return Physics.Raycast(o, Vector3.down, out var hit, 3f, RatController.Mask, QueryTriggerInteraction.Ignore) ? hit.point : W(x, y);
        }

        static Material Mat(string name, Color color, string texture = null, Vector2? tiling = null, string shader = "KitchenRat/Toon")
        {
            Directory.CreateDirectory(MatDir);
            string path = MatDir + "/" + name + ".mat";
            var m = AssetDatabase.LoadAssetAtPath<Material>(path);
            var sh = Shader.Find(shader) ?? Shader.Find("Standard");
            if (!m)
            {
                m = new Material(sh);
                AssetDatabase.CreateAsset(m, path);
            }
            m.shader = sh;
            m.color = color;
            if (texture != null)
            {
                m.mainTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(Art + "rooms/textures/" + texture + ".png");
                m.mainTextureScale = tiling ?? Vector2.one;
            }
            EditorUtility.SetDirty(m);
            return m;
        }

        static GameObject Cube(string name, Vector3 center, Vector3 size, Material m, Transform parent, bool collider = true)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            go.transform.SetParent(parent, false);
            go.transform.position = center;
            go.transform.localScale = size;
            go.GetComponent<Renderer>().sharedMaterial = m;
            if (!collider) Object.DestroyImmediate(go.GetComponent<Collider>());
            return go;
        }

        static T AddZone<T>(string name, Vector3 pos, Vector3 size, float rotY = 0f) where T : Zone
        {
            var go = new GameObject(name);
            go.transform.SetParent(root, false);
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, rotY, 0f));
            var z = go.AddComponent<T>();
            z.size = size;
            return z;
        }

        // ---------- the room ----------

        static Light Lighting()
        {
            RenderSettings.skybox = null;
            RenderSettings.ambientMode = AmbientMode.Flat;
            var pal = night.pal;
            float hemi = pal != null && pal.hemi > 0f ? pal.hemi : 0.8f;
            RenderSettings.ambientLight = new Color(0.25f, 0.27f, 0.42f) * hemi;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.03f;
            RenderSettings.fogColor = Hex(pal != null ? pal.fog : 0x0e1220);

            var moon = new GameObject("Moonlight").AddComponent<Light>();
            moon.transform.SetParent(root, false);
            moon.type = LightType.Directional;
            moon.color = new Color(0.62f, 0.7f, 1f);
            moon.intensity = 0.5f * (pal != null && pal.moon > 0f ? pal.moon : 0.9f);
            moon.shadows = LightShadows.Soft;
            moon.transform.rotation = Quaternion.Euler(38f, 165f, 0f);

            foreach (var l in night.lights)
            {
                var lt = new GameObject("Lamp light").AddComponent<Light>();
                lt.transform.SetParent(root, false);
                lt.type = LightType.Point;
                lt.color = Hex(l.c);
                lt.intensity = l.i * 1.4f;
                lt.range = l.r / 100f;
                lt.shadows = LightShadows.Soft;
                lt.transform.position = W(l.x, l.y, l.h);
            }

            // the ceiling light: off at night, the owner switches it on
            var room = new GameObject("Ceiling light (owner)").AddComponent<Light>();
            room.transform.SetParent(root, false);
            room.type = LightType.Point;
            room.color = new Color(1f, 0.93f, 0.8f);
            room.intensity = 1.6f;
            room.range = 9f;
            room.shadows = LightShadows.Soft;
            room.transform.position = W(480, 300, 200);
            room.enabled = false;
            return room;
        }

        static Color Hex(int c) => new Color(((c >> 16) & 255) / 255f, ((c >> 8) & 255) / 255f, (c & 255) / 255f);

        static int Section(float pos) => Mathf.Clamp(Mathf.FloorToInt(pos / 120f), 0, 7);

        static void Room()
        {
            string floorTex = night.pal != null && !string.IsNullOrEmpty(night.pal.floor) ? "floor_" + night.pal.floor : "floor_tile";
            string wallTex = night.pal != null && !string.IsNullOrEmpty(night.pal.wall) ? "wall_" + night.pal.wall : "wall_stripes";
            var floorMat = Mat("Floor_" + night.id, Color.white, floorTex, new Vector2(6f, 3.75f));
            var wallMat = Mat("Wall_" + night.id, Color.white, wallTex, Vector2.one);
            var ceilMat = Mat("Ceiling_" + night.id, Hex(night.pal != null ? night.pal.ceil : 0x22263a));
            var trimMat = Mat("Trim", new Color32(0x3a, 0x2e, 0x30, 255));

            var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
            floor.name = "Floor";
            floor.transform.SetParent(root, false);
            floor.transform.localScale = new Vector3(0.96f, 1f, 0.6f);
            floor.GetComponent<Renderer>().sharedMaterial = floorMat;

            var ceil = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ceil.name = "Ceiling";
            ceil.transform.SetParent(root, false);
            ceil.transform.SetPositionAndRotation(new Vector3(0f, 2.5f, 0f), Quaternion.Euler(180f, 0f, 0f));
            ceil.transform.localScale = new Vector3(0.96f, 1f, 0.6f);
            ceil.GetComponent<Renderer>().sharedMaterial = ceilMat;
            ceil.GetComponent<Renderer>().shadowCastingMode = ShadowCastingMode.Off;
            Object.DestroyImmediate(ceil.GetComponent<Collider>());

            // which wall sections get a window, the door, the mouse hole and cracks
            var north = new string[8]; var south = new string[8]; var west = new string[5]; var east = new string[5];
            if (night.window != null && night.window.w > 0f) north[Section(night.window.x + night.window.w / 2f)] = "wall_window";
            south[1] = "wall_mousehole";
            east[Mathf.Clamp(Mathf.FloorToInt((night.door > 0 ? night.door : 300) / 120f), 0, 4)] = "wall_door";
            foreach (var c in night.cracks)
            {
                if (c.wall == "s") { int i = Section(c.x); if (south[i] == null) south[i] = "wall_crack"; AddZone<HideSpot>("Crack (hide)", W(c.x, 590), new Vector3(0.44f, 0.2f, 0.18f)); }
                else if (c.wall == "n") { int i = Section(c.x); if (north[i] == null) north[i] = "wall_crack"; AddZone<HideSpot>("Crack (hide)", W(c.x, 10), new Vector3(0.44f, 0.2f, 0.18f)); }
                else if (c.wall == "w") { int j = Mathf.Clamp(Mathf.FloorToInt(c.y / 120f), 0, 4); if (west[j] == null) west[j] = "wall_crack"; AddZone<HideSpot>("Crack (hide)", W(10, c.y), new Vector3(0.44f, 0.2f, 0.18f), 90f); }
                else { int j = Mathf.Clamp(Mathf.FloorToInt(c.y / 120f), 0, 4); if (east[j] == null) east[j] = "wall_crack"; AddZone<HideSpot>("Crack (hide)", W(950, c.y), new Vector3(0.44f, 0.2f, 0.18f), 90f); }
            }
            var walls = Group("Walls");
            for (int i = 0; i < 8; i++) Wall(north[i] ?? "wall_section", 60 + 120 * i, -5, 180f, walls, wallMat);
            for (int i = 0; i < 8; i++) Wall(south[i] ?? "wall_section", 60 + 120 * i, 605, 0f, walls, wallMat);
            for (int j = 0; j < 5; j++) Wall(west[j] ?? "wall_section", -5, 60 + 120 * j, 90f, walls, wallMat);
            for (int j = 0; j < 5; j++) Wall(east[j] ?? "wall_section", 965, 60 + 120 * j, -90f, walls, wallMat);
            foreach (var (x, y) in new[] { (-5f, -5f), (965f, -5f), (-5f, 605f), (965f, 605f) })
                Cube("Corner", W(x, y, 125), new Vector3(0.1f, 2.5f, 0.1f), trimMat, walls);

            var shade = Spawn(night.lamp == "chandelier" ? "rooms/chandelier" : "rooms/lamp_shade", W(480, 300), 0f, decorRoot);
            if (shade) shade.transform.position = new Vector3(shade.transform.position.x, 2.5f - BoundsOf(shade).size.y, shade.transform.position.z);
        }

        static void Wall(string model, float x, float y, float rotY, Transform parent, Material wallMat)
        {
            var go = Spawn("rooms/" + model, W(x, y), rotY, parent);
            if (!go) return;
            Collide(go);
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++)
                    if (mats[i] && mats[i].name.StartsWith("c8a96b0")) mats[i] = wallMat;
                r.sharedMaterials = mats;
            }
        }

        static void Hide(string kind, float x, float y, float w, float d, float rotY = 0f) =>
            AddZone<HideSpot>("Under " + kind + " (hide)", W(x, y), new Vector3(w / 100f, 0.2f, d / 100f), rotY).id = kind;

        static void Furniture()
        {
            // The kitchen layout (levels.js kitchenFurniture): counters along the north and west walls, fridge, island,
            // a box as a step, the table with chairs, a low shelf and a stool.
            Furn("furniture/counter_corner", 36, 36, 180f, "counter", 72, 72);
            const float runEnd = 830f, runStart = 72f;
            int n = 12;
            float w = (runEnd - runStart) / n;
            for (int i = 0; i < n; i++) Furn(i == 6 ? "furniture/counter_sink" : "furniture/counter_section", runStart + w * (i + 0.5f), 36, 180f, "counter", w, 72);
            for (int j = 0; j < 4; j++) Furn("furniture/counter_section", 36, 72 + 60 * (j + 0.5f), 90f, "counter", 60, 72);
            Furn("furniture/fridge", 895, 56, 180f, "fridge", 130, 110);

            Furn("furniture/kitchen_island", 480, 295, 0f, "island", 200, 90);
            Furn("furniture/cardboard_box", 608, 284, 0f, "box", 44, 44, 44);
            var table = Furn("furniture/table_kitchen", 720, 445, 0f, "table", 200, 130);
            if (table)
            {
                var cloth = table.transform.Find("tablecloth");
                var spec = night.furn.FirstOrDefault(f => f.t == "table");
                if (cloth && spec != null && spec.cloth == 0) cloth.gameObject.SetActive(false);
            }
            Hide("table", 720, 445, 184, 114);
            foreach (var (x, y, r) in new[] { (596f, 420f, 90f), (596f, 472f, 90f), (846f, 446f, -90f) })
            {
                Furn("furniture/chair", x, y, r, "chair");
                Hide("chair", x, y, 28, 28);
            }
            Furn("furniture/low_shelf", 231, 325, 0f, "lowShelf", 62, 50);
            Hide("shelf", 231, 325, 54, 42);
            Furn("furniture/stool", 100, 252, 0f, "stool");
        }

        static void Decor()
        {
            foreach (var p in night.props)
            {
                switch (p.t)
                {
                    case "foil":
                        var foil = Spawn("props/foil", W(p.x + p.w / 2f, p.y + p.h / 2f), 0f, decorRoot);
                        Fit(foil, p.w, p.h);
                        AddZone<NoisyZone>("Foil (noisy)", W(p.x + p.w / 2f, p.y + p.h / 2f), new Vector3(p.w / 100f, 0.2f, p.h / 100f)).Configure("foil");
                        break;
                    case "breadbox":
                        Collide(Spawn("props/bread_box", OnTop(p.x + p.w / 2f, p.y + p.h / 2f), 180f, decorRoot));
                        break;
                    case "hum":
                        AddZone<HumZone>("Hum (masks footsteps)", W(p.x, p.y), new Vector3(p.r * 2f / 100f, 1.2f, p.r * 2f / 100f));
                        break;
                    case "noisy":
                        Noisy(p);
                        break;
                    default:
                        Debug.Log("Kitchen Rat: prop '" + p.t + "' in night " + night.number + " is not ported yet");
                        break;
                }
            }
            if (night.furn.Any(f => f.plate)) Collide(Spawn("food/plate", OnTop(680, 432), 0f, decorRoot));
            Spawn("props/cat_bed", night.Pos(night.catBed), 0f, decorRoot); // no collider: the cat lies in it
            if (night.bowl.Length >= 2) Collide(Spawn("props/cat_bowl", night.Pos(night.bowl), 0f, decorRoot));
            if (night.dock.Length >= 2) Collide(Spawn("props/vacuum_dock", night.Pos(night.dock), -90f, decorRoot));
        }

        static string NoisyModel(string kind)
        {
            switch (kind)
            {
                case "puddle": return "props/puddle";
                case "board": return "props/floorboard_worn";
                case "bag": return "props/plastic_bag";
                case "glasses": return "props/glass";
                case "bottles": return "props/bottle";
                case "popper": return "props/party_popper";
                case "balloon": return Random.value < 0.5f ? "props/balloon_red" : "props/balloon_blue";
                case "confetti": return "props/confetti";
                case "squeaky": return "props/squeaky_toy";
                case "remote": return "props/tv_remote";
                case "grain": return "props/grain_spill";
                case "cord": return "props/lamp_cord";
                case "hanger": return "props/hangers";
                case "litter": return "props/litter_box";
                case "pipe": return "props/pipe";
                case "lego": return "props/lego_bricks";
                case "musicbox": return "props/music_box";
                case "nightlight": return "props/night_light";
                default: return null; // dock: the vacuum dock is already there
            }
        }

        /// <summary>A noisy thing: a circle (x, y, r) or a rectangle (x, y = top-left corner, w, h); default radius 20 cm.</summary>
        static void Noisy(PropData p)
        {
            bool rect = p.w > 0f && p.h > 0f;
            float cx = rect ? p.x + p.w / 2f : p.x, cy = rect ? p.y + p.h / 2f : p.y;
            float r = p.r > 0f ? p.r : p.kind == "plate" ? 16f : p.kind == "remote" ? 10f : p.kind == "squeaky" ? 11f : 20f;
            Vector3 at = p.floor ? W(cx, cy) : OnTop(cx, cy);
            string model = NoisyModel(p.kind);
            GameObject go = model != null ? Spawn(model, at, Random.Range(0f, 360f), decorRoot) : null;
            if (go && rect && (p.kind == "board" || p.kind == "confetti")) { go.transform.rotation = Quaternion.identity; Fit(go, p.w, p.h); }
            var size = rect ? new Vector3(p.w / 100f, 0.2f, p.h / 100f) : new Vector3(r * 2f / 100f, 0.2f, r * 2f / 100f);
            var z = AddZone<NoisyZone>("Noisy: " + p.kind, at, size);
            z.Configure(p.kind);
            if (p.kind == "balloon" && go) z.hideWhenUsed = go;
        }

        static string KnockModel(string kind)
        {
            switch (kind)
            {
                case "cup": return "props/mug";
                case "carton": case "book": return "props/small_box";
                case "vase": return "props/jar";
                default: return "props/" + kind;
            }
        }

        static void Knockables()
        {
            foreach (var k in night.knocks)
            {
                var go = Spawn(KnockModel(k.kind), OnTop(k.x, k.y), 0f, decorRoot);
                if (!go) continue;
                go.AddComponent<BoxCollider>();
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = 0.25f;
                rb.isKinematic = true;
                var kn = go.AddComponent<Knockable>();
                kn.kind = k.kind;
                kn.trap = k.trap;
                kn.spawn = k.spawn ?? "";
                kn.pushDir = (W(k.toX, k.toY) - W(k.x, k.y)).normalized;
            }
        }

        static readonly Dictionary<string, string> FindLabels = new Dictionary<string, string>
        {
            { "button", "A shiny button! The pups will love it." }, { "sock", "A soft sock for the nest!" },
            { "photo", "An old photo of the owner as a kid." }, { "toy", "A tiny toy mouse for the pups!" },
            { "thimble", "A thimble! A perfect cup for the pups." }, { "ring", "A gold ring. The owner lost it long ago." },
            { "drawing", "A kid’s drawing… of a rat. It’s you!" }, { "letter", "A letter: “Exterminator, Saturday morning.” Uh-oh." },
            { "candle", "A birthday candle for the nest." }, { "marble", "A glass marble! The pups can roll it around." },
            { "battery", "The spare battery! His flashlight will die soon." },
        };

        static void Food()
        {
            foreach (var s in night.food.spots)
            {
                Vector3 at = s.floor ? W(s.x, s.y) : OnTop(s.x, s.y);
                var go = Spawn(KitchenRat.Food.ModelFor(s.type), at, Random.Range(0f, 360f), foodRoot);
                if (!go) continue;
                var f = go.AddComponent<Food>();
                f.type = s.type;
                f.id = s.tag ?? "";
                f.hidden = s.hidden;
            }
            foreach (var sc in night.secrets)
            {
                string model = sc.kind == "toy" ? "finds/toy_mouse" : "finds/" + sc.kind;
                if (!Load(model)) model = "finds/button";
                var go = Spawn(model, sc.floor ? W(sc.x, sc.y) : OnTop(sc.x, sc.y), Random.Range(0f, 360f), foodRoot);
                if (!go) continue;
                var f = go.AddComponent<Food>();
                f.type = sc.kind;
                f.isFind = true;
                f.label = !string.IsNullOrEmpty(sc.label) ? sc.label : FindLabels.TryGetValue(sc.kind, out var l) ? l : "A find for the nest!";
            }
        }

        static void Traps()
        {
            foreach (var t in night.trapSpots)
            {
                var go = Spawn("props/mousetrap", W(t.x, t.y), Random.Range(0f, 360f), decorRoot);
                if (go) go.AddComponent<Trap>().hidden = t.hidden;
            }
        }

        // ---------- the nest behind the mouse hole ----------

        static void NestRoom()
        {
            var nestRoot = Group("Nest");
            var soil = Mat("Nest_Soil", new Color32(0x4a, 0x36, 0x28, 255));
            var earth = Mat("Nest_Earth", new Color32(0x3a, 0x2a, 0x20, 255));
            // x 10…250, y 600…780 behind the south wall (the mouse hole is at x = 180)
            var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
            floor.name = "Nest floor";
            floor.transform.SetParent(nestRoot, false);
            floor.transform.position = W(130, 690);
            floor.transform.localScale = new Vector3(0.24f, 1f, 0.18f);
            floor.GetComponent<Renderer>().sharedMaterial = soil;
            Cube("Back", W(130, 785, 50), new Vector3(2.6f, 1f, 0.1f), earth, nestRoot);
            Cube("Side", W(5, 690, 50), new Vector3(0.1f, 1f, 1.9f), earth, nestRoot);
            Cube("Side", W(255, 690, 50), new Vector3(0.1f, 1f, 1.9f), earth, nestRoot);
            Cube("Roof", W(130, 690, 95), new Vector3(2.6f, 0.1f, 1.9f), earth, nestRoot);

            Collide(Spawn("rooms/nest", W(120, 700), 0f, nestRoot));
            var light = new GameObject("Nest light").AddComponent<Light>();
            light.transform.SetParent(nestRoot, false);
            light.type = LightType.Point;
            light.color = new Color32(0xff, 0xb0, 0x70, 255);
            light.intensity = 1.3f;
            light.range = 3f;
            light.transform.position = W(140, 690, 45);

            var spots = new[] { (95f, 690f, 20f, "sleep"), (140f, 715f, -60f, "sleep"), (110f, 725f, 150f, "idle"), (150f, 680f, 200f, "sniff") };
            foreach (var (x, y, a, clip) in spots)
            {
                var pup = Spawn("characters/rat_pup", W(x, y, 4), a, nestRoot);
                if (!pup) continue;
                SetupClips(pup, "characters/rat_pup", clip);
                pup.AddComponent<PlayClip>().clip = clip;
            }
            AddZone<NestZone>("Nest (deliver)", W(130, 692), new Vector3(2.4f, 0.9f, 1.75f));
            var hole = new GameObject("Mouse hole (kitchen side)").transform;
            hole.SetParent(root, false);
            hole.position = W(180, 585);
        }

        static ClipPlayer SetupClips(GameObject model, string path, string start)
        {
            var animator = model.GetComponent<Animator>();
            if (!animator) animator = model.AddComponent<Animator>();
            animator.applyRootMotion = false;
            animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
            var player = model.AddComponent<ClipPlayer>();
            player.clips = AssetDatabase.LoadAllAssetsAtPath(Art + path + ".fbx").OfType<AnimationClip>()
                .Where(c => !c.name.StartsWith("__preview__")).ToList();
            player.startClip = start;
            return player;
        }

        // ---------- characters, camera, game ----------

        static RatController Rat()
        {
            var go = new GameObject("Rat");
            go.transform.SetParent(root, false);
            go.transform.SetPositionAndRotation(W(150, 700, 2), Quaternion.identity); // in the nest, facing the hole
            var cc = go.AddComponent<CharacterController>();
            cc.center = new Vector3(0f, 0.062f, 0f);
            cc.radius = 0.055f;
            cc.height = 0.12f;
            cc.stepOffset = 0.035f;
            cc.skinWidth = 0.005f;
            cc.minMoveDistance = 0f;
            cc.slopeLimit = 50f;

            var model = Spawn("characters/rat_mother", go.transform.position, 0f, go.transform);
            var rat = go.AddComponent<RatController>();
            if (model)
            {
                rat.anim = SetupClips(model, "characters/rat_mother", "idle");
                var b = BoundsOf(model);
                var mouth = new GameObject("Mouth").transform;
                mouth.SetParent(go.transform, false);
                mouth.localPosition = new Vector3(0f, b.size.y * 0.35f, b.max.z - go.transform.position.z - 0.01f);
                rat.mouth = mouth;
            }
            foreach (var t in go.GetComponentsInChildren<Transform>(true)) t.gameObject.layer = RatController.IgnoreLayer;

            var marker = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            marker.name = "Jump marker";
            marker.transform.SetParent(root, false);
            marker.transform.localScale = new Vector3(0.1f, 0.002f, 0.1f);
            marker.layer = RatController.IgnoreLayer;
            Object.DestroyImmediate(marker.GetComponent<Collider>());
            var mr = marker.GetComponent<Renderer>();
            mr.sharedMaterial = Mat("Jump_Marker", new Color(1f, 0.85f, 0.2f), shader: "Unlit/Color");
            mr.shadowCastingMode = ShadowCastingMode.Off;
            marker.SetActive(false);
            rat.marker = marker.transform;
            return rat;
        }

        static CatAI Cat()
        {
            var go = new GameObject("Cat");
            go.transform.SetParent(root, false);
            go.transform.position = night.Pos(night.catBed);
            var model = Spawn("characters/cat", go.transform.position, 0f, go.transform);
            var cat = go.AddComponent<CatAI>();
            cat.eyeHeight = 0.25f;
            if (model) cat.anim = SetupClips(model, "characters/cat", "sleep");
            return cat;
        }

        static OwnerAI Owner(Light roomLight)
        {
            var go = new GameObject("Owner");
            go.transform.SetParent(root, false);
            go.transform.position = W(935, night.door > 0 ? night.door : 300);
            var model = Spawn("characters/owner", go.transform.position, 0f, go.transform);
            var owner = go.AddComponent<OwnerAI>();
            if (model) owner.anim = SetupClips(model, "characters/owner", "idle");
            var fl = new GameObject("Flashlight beam").AddComponent<Light>();
            fl.transform.SetParent(go.transform, false);
            fl.transform.localPosition = new Vector3(0.15f, 1.3f, 0.2f);
            fl.transform.localRotation = Quaternion.Euler(18f, 0f, 0f);
            fl.type = LightType.Spot;
            fl.spotAngle = 40f;
            fl.range = 6f;
            fl.intensity = 3f;
            fl.color = new Color(1f, 0.95f, 0.8f);
            fl.shadows = LightShadows.Soft;
            fl.enabled = false;
            owner.flashlight = fl;
            owner.roomLight = roomLight;
            return owner;
        }

        static Camera MakeCamera(RatController rat)
        {
            var go = new GameObject("Main Camera") { tag = "MainCamera" };
            var cam = go.AddComponent<Camera>();
            cam.nearClipPlane = 0.02f;
            cam.farClipPlane = 40f;
            cam.fieldOfView = 60f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = RenderSettings.fogColor;
            go.AddComponent<AudioListener>();
            var follow = go.AddComponent<FollowCamera>();
            follow.target = rat.transform;
            follow.yaw = 0f;
            go.transform.position = rat.transform.position + new Vector3(0f, 0.3f, -0.6f);
            return cam;
        }

        static void Game(RatController rat, FollowCamera cam, CatAI cat, OwnerAI owner)
        {
            var gm = new GameObject("Game").AddComponent<GameManager>();
            gm.nightId = night.id;
            gm.rat = rat;
            gm.followCam = cam;
            gm.cat = cat;
            gm.owner = owner;
            gm.holePoint = root.Find("Mouse hole (kitchen side)");
            var types = new List<string> { "crumb", "cheese" };
            foreach (var s in night.food.spots) if (!types.Contains(s.type)) types.Add(s.type);
            foreach (var k in night.knocks) if (!string.IsNullOrEmpty(k.spawn) && !types.Contains(k.spawn)) types.Add(k.spawn);
            gm.foodTypes = types.ToArray();
            gm.foodModels = types.Select(t => Load(KitchenRat.Food.ModelFor(t))).ToArray();
            gm.trapModel = Load("props/mousetrap");
            gm.unitScale = unit;
        }
    }

    /// <summary>Builds the kitchen nights automatically the first time the project is opened.</summary>
    [InitializeOnLoad]
    static class AutoBuild
    {
        static double next;
        static int tries;

        static AutoBuild()
        {
            if (File.Exists(KitchenBuilder.FirstScene)) return;
            EditorApplication.update += Tick;
        }

        static void Tick()
        {
            if (EditorApplication.timeSinceStartup < next) return;
            next = EditorApplication.timeSinceStartup + 1.0;
            if (EditorApplication.isCompiling || EditorApplication.isUpdating || EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (File.Exists(KitchenBuilder.FirstScene) || ++tries > 120) { EditorApplication.update -= Tick; return; }
            if (!AssetDatabase.LoadAssetAtPath<GameObject>(KitchenBuilder.Art + "furniture/fridge.fbx")) return;
            EditorApplication.update -= Tick;
            KitchenBuilder.BuildAll();
            EditorSceneManager.OpenScene(KitchenBuilder.FirstScene);
        }
    }
}
