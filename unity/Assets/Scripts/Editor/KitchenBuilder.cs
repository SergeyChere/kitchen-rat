using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace KitchenRat.EditorTools
{
    /// <summary>
    /// Builds Assets/Scenes/Kitchen.unity (night 1) from the generated models, with the layout of the prototype's kitchen
    /// (game/js/levels.js). Runs by itself the first time the project opens; rebuild any time with Kitchen Rat → Build Kitchen Scene.
    /// Positions use the prototype's room coordinates in cm: x to the east, y to the south, origin at the north-west corner.
    /// </summary>
    public static class KitchenBuilder
    {
        public const string Art = "Assets/Art/";
        public const string ScenePath = "Assets/Scenes/Kitchen.unity";
        const string MatDir = "Assets/Materials";

        static float unit = 1f;
        static Transform root, furnRoot, decorRoot, foodRoot;

        [MenuItem("Kitchen Rat/Build Kitchen Scene", priority = 1)]
        public static void BuildMenu()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            Build();
        }

        [MenuItem("Kitchen Rat/Reimport Art", priority = 20)]
        public static void ReimportArt()
        {
            AssetDatabase.ImportAsset("Assets/Art", ImportAssetOptions.ImportRecursive | ImportAssetOptions.ForceUpdate);
        }

        static Vector3 W(float x, float y, float h = 0f) => Nights.World(x, y, h);

        public static void Build()
        {
            if (!ArtUsesToon()) ReimportArt();
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            unit = MeasureUnit();
            root = new GameObject("Kitchen").transform;
            furnRoot = Group("Furniture");
            decorRoot = Group("Decor");
            foodRoot = Group("Food");

            Lighting();
            Room();
            Furniture();
            Physics.SyncTransforms();
            Decor();
            var nest = NestRoom();
            Physics.SyncTransforms();
            Knockables();
            Food();
            var rat = Rat(nest);
            var cam = MakeCamera(rat);
            rat.cameraRig = cam.transform;
            Game(rat);

            Directory.CreateDirectory("Assets/Scenes");
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            Debug.Log("Kitchen Rat: built " + ScenePath + (unit != 1f ? " (model scale corrected ×" + unit + ")" : ""));
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

        static void Lighting()
        {
            RenderSettings.skybox = null;
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.2f, 0.22f, 0.34f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.03f;
            RenderSettings.fogColor = new Color32(0x0e, 0x12, 0x20, 255);

            var moon = new GameObject("Moonlight").AddComponent<Light>();
            moon.transform.SetParent(root, false);
            moon.type = LightType.Directional;
            moon.color = new Color(0.62f, 0.7f, 1f);
            moon.intensity = 0.45f;
            moon.shadows = LightShadows.Soft;
            moon.transform.rotation = Quaternion.Euler(38f, 165f, 0f);

            var lamp = new GameObject("Night light (warm)").AddComponent<Light>();
            lamp.transform.SetParent(root, false);
            lamp.type = LightType.Point;
            lamp.color = new Color32(0xff, 0xa8, 0x60, 255);
            lamp.intensity = 1.4f;
            lamp.range = 5.2f;
            lamp.shadows = LightShadows.Soft;
            lamp.transform.position = W(900, 560, 60);
        }

        static void Room()
        {
            var floorMat = Mat("Floor_Kitchen", Color.white, "floor_tile", new Vector2(6f, 3.75f));
            var wallMat = Mat("Wall_Kitchen", Color.white, "wall_stripes", Vector2.one);
            var ceilMat = Mat("Ceiling", new Color32(0x22, 0x26, 0x3a, 255));
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

            var walls = Group("Walls");
            // north wall (behind the counters): the window in the middle
            for (int i = 0; i < 8; i++) Wall(i == 4 ? "wall_window" : "wall_section", 60 + 120 * i, -5, 180f, walls, wallMat);
            // south wall: the mouse hole to the nest and two cracks
            for (int i = 0; i < 8; i++) Wall(i == 1 ? "wall_mousehole" : i == 2 || i == 6 ? "wall_crack" : "wall_section", 60 + 120 * i, 605, 0f, walls, wallMat);
            // west wall: a crack; east wall: the door
            for (int j = 0; j < 5; j++) Wall(j == 3 ? "wall_crack" : "wall_section", -5, 60 + 120 * j, 90f, walls, wallMat);
            for (int j = 0; j < 5; j++) Wall(j == 2 ? "wall_door" : "wall_section", 965, 60 + 120 * j, -90f, walls, wallMat);
            foreach (var (x, y) in new[] { (-5f, -5f), (965f, -5f), (-5f, 605f), (965f, 605f) })
                Cube("Corner", W(x, y, 125), new Vector3(0.1f, 2.5f, 0.1f), trimMat, walls);

            // hiding spots in front of the cracks
            AddZone<HideSpot>("Crack (hide)", W(300, 592), new Vector3(0.44f, 0.2f, 0.16f));
            AddZone<HideSpot>("Crack (hide)", W(780, 592), new Vector3(0.44f, 0.2f, 0.16f));
            AddZone<HideSpot>("Crack (hide)", W(8, 420), new Vector3(0.44f, 0.2f, 0.16f), 90f);

            var shade = Spawn("rooms/lamp_shade", W(480, 300), 0f, decorRoot);
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

        static void Furniture()
        {
            // counters along the north wall and down the west wall, with a corner piece and a sink
            Furn("furniture/counter_corner", 36, 36, 180f, "counter", 72, 72);
            const float runEnd = 830f, runStart = 72f;
            int n = 12;
            float w = (runEnd - runStart) / n;
            for (int i = 0; i < n; i++) Furn(i == 6 ? "furniture/counter_sink" : "furniture/counter_section", runStart + w * (i + 0.5f), 36, 180f, "counter", w, 72);
            for (int j = 0; j < 4; j++) Furn("furniture/counter_section", 36, 72 + 60 * (j + 0.5f), 90f, "counter", 60, 72);
            Furn("furniture/fridge", 895, 56, 180f, "fridge", 130, 110);

            Furn("furniture/kitchen_island", 480, 295, 0f, "island", 200, 90);
            Furn("furniture/cardboard_box", 608, 284, 0f, "box", 44, 44, 44);
            Furn("furniture/table_kitchen", 720, 445, 0f, "table", 200, 130);
            Furn("furniture/chair", 596, 420, 90f, "chair");
            Furn("furniture/chair", 596, 472, 90f, "chair");
            Furn("furniture/chair", 846, 446, -90f, "chair");
            Furn("furniture/low_shelf", 231, 325, 0f, "lowShelf", 62, 50);
            Furn("furniture/stool", 100, 252, 0f, "stool");
        }

        static void Decor()
        {
            // foil on the floor: noisy unless you sneak
            var foil = Spawn("props/foil", W(230, 414), 0f, decorRoot);
            Fit(foil, 160, 56);
            AddZone<NoisyZone>("Foil (noisy)", W(230, 414), new Vector3(1.6f, 0.2f, 0.56f));

            Collide(Spawn("props/bread_box", OnTop(168, 27), 180f, decorRoot));
            Collide(Spawn("food/plate", OnTop(680, 432), 0f, decorRoot));
            Collide(Spawn("props/cat_bed", W(470, 545), 0f, decorRoot));
            Collide(Spawn("props/cat_bowl", W(770, 215), 0f, decorRoot));
            Collide(Spawn("props/vacuum_dock", W(900, 430), -90f, decorRoot));
        }

        static void Knockables()
        {
            Knock("props/mug", "cup", 655, 398, 655, 362, trap: true); // on the edge of the table: walk past without sneaking and it falls
            Knock("props/jar", "jar", 470, 60, 470, 102);
            Knock("props/apple", "apple", 520, 330, 522, 364);
        }

        static void Knock(string model, string kind, float x, float y, float tx, float ty, bool trap = false)
        {
            var go = Spawn(model, OnTop(x, y), 0f, decorRoot);
            if (!go) return;
            go.AddComponent<BoxCollider>();
            var rb = go.AddComponent<Rigidbody>();
            rb.mass = 0.25f;
            rb.isKinematic = true;
            var k = go.AddComponent<Knockable>();
            k.kind = kind;
            k.trap = trap;
            k.pushDir = (W(tx, ty) - W(x, y)).normalized;
        }

        static void Food()
        {
            var night = Nights.Get("kitchen");
            foreach (var s in night.spots)
            {
                string model = s.kind == FoodKind.Cheese ? "food/cheese" : s.kind == FoodKind.Crumb ? "food/crumb" : "finds/" + s.id;
                var go = Spawn(model, OnTop(s.x, s.y), Random.Range(0f, 360f), foodRoot);
                if (!go) continue;
                var f = go.AddComponent<Food>();
                f.kind = s.kind;
                f.id = s.id;
                f.hidden = s.hidden;
                f.flag = s.flag;
                if (s.kind == FoodKind.Find) f.label = "A shiny " + s.id + "! The pups will love it.";
            }
        }

        // ---------- the nest behind the mouse hole ----------

        static Zone NestRoom()
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

            // four pups
            var spots = new[] { (95f, 690f, 20f, "sleep"), (140f, 715f, -60f, "sleep"), (110f, 725f, 150f, "idle"), (150f, 680f, 200f, "sniff") };
            foreach (var (x, y, a, clip) in spots)
            {
                var pup = Spawn("characters/rat_pup", W(x, y, 4), a, nestRoot);
                if (!pup) continue;
                SetupClips(pup, "characters/rat_pup", clip);
                pup.AddComponent<PlayClip>().clip = clip;
            }
            return AddZone<NestZone>("Nest (deliver)", W(130, 692), new Vector3(2.4f, 0.9f, 1.75f));
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

        // ---------- rat, camera, game ----------

        static RatController Rat(Zone nest)
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

        static Camera MakeCamera(RatController rat)
        {
            var go = new GameObject("Main Camera") { tag = "MainCamera" };
            var cam = go.AddComponent<Camera>();
            cam.nearClipPlane = 0.02f;
            cam.farClipPlane = 40f;
            cam.fieldOfView = 60f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(0x0e, 0x12, 0x20, 255);
            go.AddComponent<AudioListener>();
            var follow = go.AddComponent<FollowCamera>();
            follow.target = rat.transform;
            follow.yaw = 0f;
            go.transform.position = rat.transform.position + new Vector3(0f, 0.3f, -0.6f);
            return cam;
        }

        static void Game(RatController rat)
        {
            var gm = new GameObject("Game").AddComponent<GameManager>();
            gm.nightId = "kitchen";
            gm.rat = rat;
            gm.crumbModel = Load("food/crumb");
            gm.cheeseModel = Load("food/cheese");
            gm.unitScale = unit;
        }
    }

    /// <summary>Builds the kitchen scene automatically the first time the project is opened.</summary>
    [InitializeOnLoad]
    static class AutoBuild
    {
        static double next;
        static int tries;

        static AutoBuild()
        {
            if (File.Exists(KitchenBuilder.ScenePath)) return;
            EditorApplication.update += Tick;
        }

        static void Tick()
        {
            if (EditorApplication.timeSinceStartup < next) return;
            next = EditorApplication.timeSinceStartup + 1.0;
            if (EditorApplication.isCompiling || EditorApplication.isUpdating || EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (File.Exists(KitchenBuilder.ScenePath) || ++tries > 120) { EditorApplication.update -= Tick; return; }
            if (!AssetDatabase.LoadAssetAtPath<GameObject>(KitchenBuilder.Art + "furniture/fridge.fbx")) return;
            EditorApplication.update -= Tick;
            KitchenBuilder.Build();
            EditorSceneManager.OpenScene(KitchenBuilder.ScenePath);
        }
    }
}
