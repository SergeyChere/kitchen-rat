using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Меню «Rat Kitchen → Build Scene» в редакторе Unity.
/// Строит всю сцену из простых фигур: кухню, нору с крысятами, крысу, кота, свет и связи между скриптами.
/// Сцена сохраняется в Assets/RatKitchen/Scenes/RatKitchen.unity и добавляется в Build Settings.
///
/// Координаты: 1 единица = 1 метр. Кухня 9.6 × 6 м (с точки зрения крысы огромная),
/// пол на y = 0, нора за южной стеной (z &lt; 0).
/// </summary>
public static class KitchenBuilder
{
    const string Root = "Assets/RatKitchen";
    static Dictionary<string, Material> mats;

    // Позиция из «прототипных» координат (как в браузерной версии, в сантиметрах).
    static Vector3 P(float x, float y, float h = 0f) { return new Vector3(x * 0.01f, h, (600f - y) * 0.01f); }

    [MenuItem("Rat Kitchen/Build Scene")]
    public static void Build()
    {
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        EnsureFolder(Root);
        EnsureFolder(Root + "/Materials");
        EnsureFolder(Root + "/Scenes");
        mats = new Dictionary<string, Material>();

        var world = new GameObject("Kitchen").transform;
        var nestRoot = new GameObject("Nest").transform;

        BuildLighting();
        BuildKitchen(world);
        Transform nestCenter, motherSleep, pileCenter;
        Transform[] introPath;
        List<Pup> pups = BuildNest(nestRoot, out nestCenter, out motherSleep, out pileCenter, out introPath);

        // нора (вход со стороны кухни) и точка появления
        var hole = new GameObject("MouseHole").transform;
        hole.position = P(46, 574);
        var spawn = new GameObject("KitchenSpawn").transform;
        spawn.position = hole.position + new Vector3(0.22f, 0f, 0.22f);
        spawn.rotation = Quaternion.Euler(0f, 45f, 0f);

        RatController rat = BuildRat(motherSleep);
        CatAI cat = BuildCat();
        FoodItem crumb, cheese;
        BuildFoodTemplates(out crumb, out cheese);

        // камера
        var camGo = new GameObject("Main Camera");
        camGo.tag = "MainCamera";
        var cam = camGo.AddComponent<Camera>();
        cam.nearClipPlane = 0.01f;
        cam.farClipPlane = 40f;
        cam.fieldOfView = 62f;
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.05f, 0.055f, 0.07f);
        camGo.AddComponent<AudioListener>();
        var tpc = camGo.AddComponent<ThirdPersonCamera>();
        tpc.target = rat.transform;
        camGo.transform.position = new Vector3(4.8f, 2f, -1f);

        // главный скрипт
        var gm = new GameObject("GameManager").AddComponent<GameManager>();
        gm.rat = rat;
        gm.cat = cat;
        gm.cam = tpc;
        gm.hole = hole;
        gm.kitchenSpawn = spawn;
        gm.nestCenter = nestCenter;
        gm.motherSleep = motherSleep;
        gm.pileCenter = pileCenter;
        gm.introPath = introPath;
        gm.pups = pups.ToArray();
        gm.crumbTemplate = crumb;
        gm.cheeseTemplate = cheese;

        string path = Root + "/Scenes/RatKitchen.unity";
        EditorSceneManager.SaveScene(scene, path);
        var list = new List<EditorBuildSettingsScene>(EditorBuildSettings.scenes);
        list.RemoveAll(s => s.path == path);
        list.Insert(0, new EditorBuildSettingsScene(path, true));
        EditorBuildSettings.scenes = list.ToArray();
        AssetDatabase.SaveAssets();

        EditorUtility.DisplayDialog("Крыса на кухне",
            "Сцена построена и сохранена:\n" + path + "\n\nНажми Play, чтобы играть.", "Отлично");
    }

    // ───────────────────────── свет ─────────────────────────

    static void BuildLighting()
    {
        RenderSettings.skybox = null;
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.26f, 0.3f, 0.42f);
        RenderSettings.ambientEquatorColor = new Color(0.17f, 0.17f, 0.2f);
        RenderSettings.ambientGroundColor = new Color(0.1f, 0.09f, 0.08f);
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogColor = new Color(0.05f, 0.055f, 0.07f);
        RenderSettings.fogStartDistance = 3.5f;
        RenderSettings.fogEndDistance = 13f;

        var moon = new GameObject("Moonlight").AddComponent<Light>();
        moon.type = LightType.Directional;
        moon.color = new Color(0.67f, 0.73f, 0.9f);
        moon.intensity = 0.65f;
        moon.shadows = LightShadows.Soft;
        moon.transform.rotation = Quaternion.Euler(42f, 200f, 0f);

        PointLight("NightLight", P(900, 560, 0.6f), new Color(1f, 0.7f, 0.42f), 5.2f, 1.3f);
        PointLight("HoleGlow", P(46, 564, 0.18f), new Color(0.95f, 0.76f, 0.31f), 1.2f, 1.6f);
        PointLight("NestLight", P(140, 705, 0.45f), new Color(1f, 0.69f, 0.44f), 3.2f, 2.2f);
    }

    static void PointLight(string name, Vector3 pos, Color c, float range, float intensity)
    {
        var l = new GameObject(name).AddComponent<Light>();
        l.type = LightType.Point;
        l.color = c;
        l.range = range;
        l.intensity = intensity;
        l.shadows = LightShadows.None;
        l.transform.position = pos;
    }

    // ───────────────────────── кухня ─────────────────────────

    static void BuildKitchen(Transform root)
    {
        // пол в клетку
        var floor = Prim(PrimitiveType.Plane, "Floor", root, new Vector3(4.8f, 0f, 3f), new Vector3(0.96f, 1f, 0.6f), FloorMaterial(), true);
        floor.isStatic = true;

        // стены
        var wall = Mat("Wall", new Color(0.35f, 0.37f, 0.42f));
        Box("Wall_North", root, new Vector3(4.8f, 1.3f, 6.05f), new Vector3(9.8f, 2.6f, 0.1f), wall);
        Box("Wall_South", root, new Vector3(4.8f, 1.3f, -0.05f), new Vector3(9.8f, 2.6f, 0.1f), wall);
        Box("Wall_West", root, new Vector3(-0.05f, 1.3f, 3f), new Vector3(0.1f, 2.6f, 6f), wall);
        Box("Wall_East", root, new Vector3(9.65f, 1.3f, 3f), new Vector3(0.1f, 2.6f, 6f), wall);
        var baseM = Mat("Baseboard", new Color(0.29f, 0.23f, 0.18f));
        Box("Baseboard_S", root, new Vector3(4.8f, 0.05f, 0.01f), new Vector3(9.6f, 0.1f, 0.02f), baseM, false);
        Box("Baseboard_W", root, new Vector3(0.01f, 0.05f, 3f), new Vector3(0.02f, 0.1f, 6f), baseM, false);
        Box("Baseboard_E", root, new Vector3(9.59f, 0.05f, 3f), new Vector3(0.02f, 0.1f, 6f), baseM, false);

        // окно с лунным светом
        Box("Window", root, new Vector3(5.2f, 1.7f, 5.995f), new Vector3(2.2f, 1.1f, 0.01f),
            Mat("WindowGlow", new Color(0.3f, 0.36f, 0.5f), 0.9f, 0f, new Color(0.25f, 0.3f, 0.45f)), false);

        // дыра в стене и светящееся кольцо у входа
        var black = Mat("HoleBlack", Color.black, 0f);
        var h1 = Cyl("HoleOpening", root, P(46, 600, 0f) + new Vector3(0f, 0f, 0.004f), 0.2f, 0.005f, black, false);
        h1.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
        var h2 = Cyl("HoleOpening_Nest", root, P(46, 600, 0f) + new Vector3(0f, 0f, -0.104f), 0.2f, 0.005f, black, false);
        h2.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
        Cyl("HoleRing", root, P(46, 574, 0.001f), 0.34f, 0.002f,
            Mat("HoleRing", new Color(0.4f, 0.32f, 0.12f), 0.3f, 0f, new Color(0.35f, 0.26f, 0.07f)), false);

        // столешницы, холодильник, тумба
        var cBody = Mat("CounterBody", new Color(0.36f, 0.29f, 0.24f));
        var cTop = Mat("CounterTop", new Color(0.6f, 0.54f, 0.46f), 0.5f);
        Counter(root, "Counter_North", 0, 0, 960, 72, cBody, cTop);
        Counter(root, "Counter_West", 0, 72, 72, 240, cBody, cTop);
        Box("Fridge", root, P(895, 127, 0.9f), new Vector3(1.3f, 1.8f, 1.1f), Mat("Fridge", new Color(0.84f, 0.85f, 0.87f), 0.6f));
        Box("FridgeHandle", root, P(848, 184, 1.1f), new Vector3(0.04f, 0.5f, 0.04f), Mat("Metal", new Color(0.6f, 0.62f, 0.66f), 0.7f, 0.6f), false);
        Counter(root, "Island", 380, 250, 200, 90, Mat("IslandBody", new Color(0.3f, 0.25f, 0.2f)), cTop);
        Sph("Apple", root, P(520, 295, 0.99f), Vector3.one * 0.18f, Mat("Apple", new Color(0.7f, 0.23f, 0.18f), 0.5f));
        Sph("Bowl", root, P(440, 295, 0.95f), new Vector3(0.32f, 0.12f, 0.32f), Mat("Bowl", new Color(0.91f, 0.89f, 0.82f), 0.6f));
        Box("Sink", root, P(305, 36, 0.905f), new Vector3(0.9f, 0.02f, 0.44f), Mat("Metal", Color.gray), false);
        Box("Stove", root, P(620, 36, 0.91f), new Vector3(1.2f, 0.03f, 0.52f), Mat("Stove", new Color(0.11f, 0.11f, 0.13f), 0.7f), false);

        // укрытия: стол, стулья, полка
        var wood = Mat("Wood", new Color(0.48f, 0.33f, 0.21f), 0.3f);
        var darkWood = Mat("DarkWood", new Color(0.37f, 0.25f, 0.15f), 0.3f);
        var table = Group(root, "Table");
        Box("Top", table, P(720, 445, 0.74f), new Vector3(2f, 0.05f, 1.3f), wood);
        Legs(table, 620, 380, 200, 130, 8, 0.03f, 0.72f, darkWood);
        Cyl("Plate", table, P(680, 430, 0.775f), 0.15f, 0.02f, Mat("Plate", new Color(0.87f, 0.84f, 0.77f), 0.6f), false);
        HideArea(table, 620, 380, 200, 130);

        Chair(root, "Chair_1", 580, 404, -1, wood, darkWood);
        Chair(root, "Chair_2", 580, 456, -1, wood, darkWood);
        Chair(root, "Chair_3", 830, 430, 1, wood, darkWood);

        var shelf = Group(root, "LowShelf");
        Box("Top", shelf, P(231, 325, 0.24f), new Vector3(0.62f, 0.04f, 0.5f), Mat("Shelf", new Color(0.56f, 0.45f, 0.28f)));
        Legs(shelf, 200, 300, 62, 50, 4, 0.02f, 0.22f, darkWood);
        Cyl("Jar", shelf, P(241, 325, 0.35f), 0.09f, 0.18f, Mat("Jar", new Color(0.42f, 0.56f, 0.54f), 0.7f), false);
        HideArea(shelf, 200, 300, 62, 50);
    }

    static void Counter(Transform root, string name, float x, float y, float w, float h, Material body, Material top)
    {
        var g = Group(root, name);
        Box("Body", g, P(x + w / 2, y + h / 2, 0.43f), new Vector3(w * 0.01f, 0.86f, h * 0.01f), body);
        Box("Top", g, P(x + w / 2, y + h / 2, 0.88f), new Vector3(w * 0.01f + 0.04f, 0.04f, h * 0.01f + 0.04f), top);
    }

    static void Chair(Transform root, string name, float x, float y, int backSide, Material wood, Material dark)
    {
        var g = Group(root, name);
        Box("Seat", g, P(x + 16, y + 16, 0.44f), new Vector3(0.32f, 0.04f, 0.32f), wood);
        Legs(g, x, y, 32, 32, 3, 0.018f, 0.42f, dark);
        float bx = backSide < 0 ? x + 2 : x + 30;
        Box("Back", g, P(bx, y + 16, 0.66f), new Vector3(0.03f, 0.4f, 0.32f), dark);
        HideArea(g, x, y, 32, 32);
    }

    static void Legs(Transform parent, float x, float y, float w, float h, float inset, float radius, float height, Material m)
    {
        float[,] c = { { inset, inset }, { w - inset, inset }, { inset, h - inset }, { w - inset, h - inset } };
        for (int i = 0; i < 4; i++)
            Cyl("Leg" + i, parent, P(x + c[i, 0], y + c[i, 1], height / 2f), radius, height, m, true);
    }

    /// <summary>Укрытие для крысы + невидимый барьер для кота на той же площади.</summary>
    static void HideArea(Transform parent, float x, float y, float w, float h)
    {
        var hz = new GameObject("HideZone");
        hz.transform.SetParent(parent, false);
        hz.transform.position = P(x + w / 2, y + h / 2, 0.3f);
        var box = hz.AddComponent<BoxCollider>();
        box.size = new Vector3(w * 0.01f, 0.6f, h * 0.01f);
        box.isTrigger = true;
        hz.AddComponent<HideZone>();

        var cb = new GameObject("CatBlocker");
        cb.transform.SetParent(parent, false);
        cb.transform.position = P(x + w / 2, y + h / 2, 0.25f);
        var cbox = cb.AddComponent<BoxCollider>();
        cbox.size = new Vector3(w * 0.01f, 0.5f, h * 0.01f);
        cb.AddComponent<CatBlocker>();
    }

    // ───────────────────────── нора ─────────────────────────

    static List<Pup> BuildNest(Transform root, out Transform center, out Transform motherSleep, out Transform pileCenter, out Transform[] introPath)
    {
        var earth = Mat("Earth", new Color(0.23f, 0.16f, 0.12f), 0f);
        var soil = Mat("Soil", new Color(0.29f, 0.21f, 0.15f), 0f);
        // нора: x 0.1..2.5, z -0.12..-1.82
        Box("NestFloor", root, new Vector3(1.3f, -0.025f, -0.97f), new Vector3(2.4f, 0.05f, 1.7f), soil);
        Box("NestWall_Back", root, new Vector3(1.3f, 0.45f, -1.87f), new Vector3(2.6f, 0.9f, 0.1f), earth);
        Box("NestWall_West", root, new Vector3(0.05f, 0.45f, -0.97f), new Vector3(0.1f, 0.9f, 1.7f), earth);
        Box("NestWall_East", root, new Vector3(2.55f, 0.45f, -0.97f), new Vector3(0.1f, 0.9f, 1.7f), earth);
        Box("NestRoof", root, new Vector3(1.3f, 0.95f, -0.97f), new Vector3(2.6f, 0.1f, 1.8f), earth);

        center = new GameObject("NestCenter").transform;
        center.SetParent(root, false);
        center.position = new Vector3(1.2f, 0f, -1.05f);
        Vector3 c = center.position;

        // подстилка из рваной бумаги, носок, крышка, пуговица
        Sph("Bedding", root, c + new Vector3(0f, 0f, 0f), new Vector3(0.92f, 0.1f, 0.72f), Mat("Bedding", new Color(0.54f, 0.44f, 0.35f), 0f));
        Color[] paper = { new Color(0.85f, 0.8f, 0.71f), new Color(0.78f, 0.73f, 0.63f), new Color(0.9f, 0.86f, 0.78f), new Color(0.62f, 0.7f, 0.78f) };
        var rnd = new System.Random(7);
        for (int i = 0; i < 26; i++)
        {
            float a = (float)rnd.NextDouble() * Mathf.PI * 2f, r = 0.2f + (float)rnd.NextDouble() * 0.34f;
            var p = Box("Paper" + i, root, c + new Vector3(Mathf.Cos(a) * r, 0.01f + (float)rnd.NextDouble() * 0.03f, Mathf.Sin(a) * r * 0.75f),
                new Vector3(0.1f + (float)rnd.NextDouble() * 0.12f, 0.012f, 0.03f + (float)rnd.NextDouble() * 0.03f), Mat("Paper" + (i % 4), paper[i % 4]), false);
            p.transform.rotation = Quaternion.Euler((float)rnd.NextDouble() * 20f, (float)rnd.NextDouble() * 360f, (float)rnd.NextDouble() * 20f);
        }
        var sock = Cyl("Sock", root, c + new Vector3(0.75f, 0.07f, -0.4f), 0.07f, 0.4f, Mat("Sock", new Color(0.42f, 0.5f, 0.65f)), false);
        sock.transform.rotation = Quaternion.Euler(0f, 35f, 90f);
        Cyl("BottleCap", root, c + new Vector3(-0.8f, 0.02f, -0.3f), 0.06f, 0.04f, Mat("Cap", new Color(0.7f, 0.23f, 0.18f), 0.6f), false);
        Cyl("Button", root, c + new Vector3(0.6f, 0.01f, 0.45f), 0.05f, 0.02f, Mat("ButtonGold", new Color(0.9f, 0.75f, 0.42f), 0.6f), false);

        // крысята
        var pups = new List<Pup>();
        Vector3[] spots = { new Vector3(-0.18f, 0f, 0.14f), new Vector3(-0.26f, 0f, -0.08f), new Vector3(-0.06f, 0f, -0.2f), new Vector3(0.08f, 0f, 0.2f) };
        Color[] fur = { new Color(0.73f, 0.64f, 0.63f), new Color(0.65f, 0.59f, 0.57f), new Color(0.77f, 0.69f, 0.67f), new Color(0.62f, 0.57f, 0.55f) };
        for (int i = 0; i < spots.Length; i++)
        {
            Transform body, head, tail, mouth; Transform[] eyes;
            var pup = BuildRodent("Pup" + (i + 1), 0.55f, Mat("PupFur" + i, fur[i]), out body, out head, out tail, out mouth, out eyes);
            pup.transform.SetParent(root, false);
            pup.transform.position = c + spots[i];
            pup.transform.rotation = Quaternion.Euler(0f, i * 97f + 20f, 0f);
            var comp = pup.AddComponent<Pup>();
            comp.head = head;
            comp.tailPivot = tail;
            pups.Add(comp);
        }

        motherSleep = new GameObject("MotherSleep").transform;
        motherSleep.SetParent(root, false);
        motherSleep.position = c + new Vector3(0.3f, 0f, 0.05f);
        motherSleep.rotation = Quaternion.Euler(0f, -100f, 0f);

        pileCenter = new GameObject("FoodPile").transform;
        pileCenter.SetParent(root, false);
        pileCenter.position = c + new Vector3(0.1f, 0f, 0f);

        Vector3[] path = { new Vector3(1.1f, 0f, -0.5f), new Vector3(0.5f, 0f, -0.26f), new Vector3(0.46f, 0f, -0.14f) };
        introPath = new Transform[path.Length];
        for (int i = 0; i < path.Length; i++)
        {
            var t = new GameObject("IntroPath" + i).transform;
            t.SetParent(root, false);
            t.position = path[i];
            introPath[i] = t;
        }
        return pups;
    }

    // ───────────────────────── персонажи ─────────────────────────

    /// <summary>Крыса из примитивов, смотрит вдоль +Z. Без коллайдеров у частей.</summary>
    static GameObject BuildRodent(string name, float s, Material furM, out Transform body, out Transform head, out Transform tailPivot, out Transform mouth, out Transform[] eyes)
    {
        var root = new GameObject(name);
        var pink = Mat("Pink", new Color(0.85f, 0.65f, 0.65f), 0.3f);
        var eyeM = Mat("RatEye", new Color(0.05f, 0.05f, 0.05f), 0.9f);

        body = Sph("Body", root.transform, new Vector3(0f, 0.07f * s, 0f), new Vector3(0.14f, 0.13f, 0.22f) * s, furM).transform;

        head = new GameObject("Head").transform;
        head.SetParent(root.transform, false);
        head.localPosition = new Vector3(0f, 0.08f * s, 0.1f * s);
        Sph("Skull", head, new Vector3(0f, 0f, 0.02f * s), new Vector3(0.09f, 0.09f, 0.14f) * s, furM);
        Sph("EarL", head, new Vector3(-0.04f * s, 0.045f * s, -0.01f * s), new Vector3(0.06f, 0.06f, 0.015f) * s, pink);
        Sph("EarR", head, new Vector3(0.04f * s, 0.045f * s, -0.01f * s), new Vector3(0.06f, 0.06f, 0.015f) * s, pink);
        var e1 = Sph("EyeL", head, new Vector3(-0.026f * s, 0.017f * s, 0.07f * s), Vector3.one * 0.02f * s, eyeM).transform;
        var e2 = Sph("EyeR", head, new Vector3(0.026f * s, 0.017f * s, 0.07f * s), Vector3.one * 0.02f * s, eyeM).transform;
        eyes = new[] { e1, e2 };
        Sph("Nose", head, new Vector3(0f, 0f, 0.09f * s), Vector3.one * 0.028f * s, pink);

        tailPivot = new GameObject("TailPivot").transform;
        tailPivot.SetParent(root.transform, false);
        tailPivot.localPosition = new Vector3(0f, 0.05f * s, -0.1f * s);
        var tail = Cyl("Tail", tailPivot, new Vector3(0f, -0.01f * s, -0.12f * s), 0.008f * s, 0.24f * s, pink, false);
        tail.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);

        mouth = new GameObject("Mouth").transform;
        mouth.SetParent(root.transform, false);
        mouth.localPosition = new Vector3(0f, 0.06f * s, 0.19f * s);
        return root;
    }

    static RatController BuildRat(Transform startAt)
    {
        Transform body, head, tail, mouth; Transform[] eyes;
        var go = BuildRodent("Rat", 1f, Mat("RatFur", new Color(0.56f, 0.54f, 0.53f)), out body, out head, out tail, out mouth, out eyes);
        go.transform.position = startAt.position;
        go.transform.rotation = startAt.rotation;
        var cc = go.AddComponent<CharacterController>();
        cc.radius = 0.07f;
        cc.height = 0.14f;
        cc.center = new Vector3(0f, 0.07f, 0f);
        cc.skinWidth = 0.005f;
        cc.stepOffset = 0.03f;
        cc.minMoveDistance = 0f;
        var rc = go.AddComponent<RatController>();
        rc.body = body; rc.head = head; rc.tailPivot = tail; rc.mouth = mouth; rc.eyes = eyes;
        return rc;
    }

    static CatAI BuildCat()
    {
        var root = new GameObject("Cat");
        var t = root.transform;
        var orange = Mat("CatFur", new Color(0.88f, 0.55f, 0.24f));
        var stripe = Mat("CatStripe", new Color(0.72f, 0.41f, 0.16f));
        Sph("Body", t, new Vector3(0f, 0.22f, 0f), new Vector3(0.26f, 0.26f, 0.48f), orange);
        for (int i = 0; i < 3; i++)
            Box("Stripe" + i, t, new Vector3(0f, 0.345f, -0.1f + i * 0.1f), new Vector3(0.2f, 0.02f, 0.03f), stripe, false);
        Sph("Head", t, new Vector3(0f, 0.32f, 0.24f), Vector3.one * 0.2f, orange);
        var earL = Box("EarL", t, new Vector3(-0.06f, 0.42f, 0.22f), new Vector3(0.06f, 0.06f, 0.02f), orange, false);
        earL.transform.localRotation = Quaternion.Euler(0f, 0f, 45f);
        var earR = Box("EarR", t, new Vector3(0.06f, 0.42f, 0.22f), new Vector3(0.06f, 0.06f, 0.02f), orange, false);
        earR.transform.localRotation = Quaternion.Euler(0f, 0f, 45f);
        var eyeMat = Mat("CatEye", new Color(0.6f, 0.88f, 0.42f), 0.9f, 0f, new Color(0.6f, 0.88f, 0.42f) * 1.5f);
        var eyeL = Sph("EyeL", t, new Vector3(-0.045f, 0.34f, 0.33f), Vector3.one * 0.04f, eyeMat).GetComponent<Renderer>();
        var eyeR = Sph("EyeR", t, new Vector3(0.045f, 0.34f, 0.33f), Vector3.one * 0.04f, eyeMat).GetComponent<Renderer>();

        var legs = new List<Transform>();
        Vector3[] lp = { new Vector3(0.07f, 0.07f, 0.14f), new Vector3(-0.07f, 0.07f, 0.14f), new Vector3(0.07f, 0.07f, -0.14f), new Vector3(-0.07f, 0.07f, -0.14f) };
        foreach (var p in lp) legs.Add(Cyl("Leg", t, p, 0.03f, 0.14f, orange, false).transform);

        var tailPivot = new GameObject("TailPivot").transform;
        tailPivot.SetParent(t, false);
        tailPivot.localPosition = new Vector3(0f, 0.26f, -0.22f);
        var tail = Cyl("Tail", tailPivot, new Vector3(0f, 0.13f, -0.075f), 0.025f, 0.3f, orange, false);
        tail.transform.localRotation = Quaternion.Euler(-30f, 0f, 0f);

        root.transform.position = P(700, 200);
        root.transform.rotation = Quaternion.Euler(0f, -90f, 0f);
        var cc = root.AddComponent<CharacterController>();
        cc.radius = 0.16f;
        cc.height = 0.4f;
        cc.center = new Vector3(0f, 0.2f, 0f);
        cc.skinWidth = 0.01f;
        cc.stepOffset = 0.05f;
        cc.minMoveDistance = 0f;

        var ai = root.AddComponent<CatAI>();
        ai.legs = legs.ToArray();
        ai.tailPivot = tailPivot;
        ai.eyeRenderers = new[] { eyeL, eyeR };

        // маршрут патруля
        var wpRoot = new GameObject("CatWaypoints").transform;
        float[,] wps = { { 150, 150 }, { 320, 180 }, { 700, 200 }, { 880, 260 }, { 880, 545 }, { 560, 552 }, { 300, 450 }, { 120, 480 } };
        var wpList = new Transform[wps.GetLength(0)];
        for (int i = 0; i < wpList.Length; i++)
        {
            var w = new GameObject("Waypoint" + i).transform;
            w.SetParent(wpRoot, false);
            w.position = P(wps[i, 0], wps[i, 1]);
            wpList[i] = w;
        }
        ai.waypoints = wpList;
        ai.startWaypoint = 3;

        // конус зрения
        var coneGo = new GameObject("CatVisionCone");
        coneGo.AddComponent<MeshFilter>();
        var mr = coneGo.AddComponent<MeshRenderer>();
        mr.shadowCastingMode = ShadowCastingMode.Off;
        mr.receiveShadows = false;
        mr.sharedMaterial = ConeMaterial();
        coneGo.AddComponent<VisionCone>().cat = ai;
        return ai;
    }

    static void BuildFoodTemplates(out FoodItem crumb, out FoodItem cheese)
    {
        var templates = new GameObject("FoodTemplates (не трогать)").transform;
        var c = Sph("Crumb", templates, Vector3.zero, new Vector3(0.07f, 0.05f, 0.07f),
            Mat("Crumb", new Color(0.85f, 0.73f, 0.54f), 0.2f, 0f, new Color(0.23f, 0.16f, 0.07f)));
        crumb = c.AddComponent<FoodItem>();
        crumb.value = 1; crumb.weight = 1;
        var ch = Box("Cheese", templates, Vector3.zero, new Vector3(0.13f, 0.08f, 0.09f),
            Mat("Cheese", new Color(0.95f, 0.76f, 0.31f), 0.4f, 0f, new Color(0.35f, 0.25f, 0.06f)), false);
        cheese = ch.AddComponent<FoodItem>();
        cheese.value = 5; cheese.weight = 2;
    }

    // ───────────────────────── помощники ─────────────────────────

    static Transform Group(Transform parent, string name)
    {
        var g = new GameObject(name).transform;
        g.SetParent(parent, false);
        return g;
    }

    static GameObject Prim(PrimitiveType type, string name, Transform parent, Vector3 worldPos, Vector3 scale, Material m, bool keepCollider)
    {
        var g = GameObject.CreatePrimitive(type);
        g.name = name;
        g.transform.SetParent(parent, false);
        g.transform.position = worldPos;
        g.transform.localScale = scale;
        g.GetComponent<Renderer>().sharedMaterial = m;
        if (!keepCollider) Object.DestroyImmediate(g.GetComponent<Collider>());
        return g;
    }

    /// <summary>Для частей персонажей позиция локальная, для мебели — мировая (родители стоят в нуле).</summary>
    static GameObject Box(string n, Transform p, Vector3 pos, Vector3 size, Material m, bool collider = true)
    {
        var g = Prim(PrimitiveType.Cube, n, p, Vector3.zero, size, m, collider);
        g.transform.localPosition = pos;
        return g;
    }

    static GameObject Sph(string n, Transform p, Vector3 pos, Vector3 size, Material m)
    {
        var g = Prim(PrimitiveType.Sphere, n, p, Vector3.zero, size, m, false);
        g.transform.localPosition = pos;
        return g;
    }

    static GameObject Cyl(string n, Transform p, Vector3 pos, float radius, float height, Material m, bool collider)
    {
        var g = Prim(PrimitiveType.Cylinder, n, p, Vector3.zero, new Vector3(radius * 2f, height / 2f, radius * 2f), m, collider);
        g.transform.localPosition = pos;
        return g;
    }

    static bool IsUrp()
    {
        return GraphicsSettings.currentRenderPipeline != null && Shader.Find("Universal Render Pipeline/Lit") != null;
    }

    static Material Mat(string name, Color c, float smooth = 0.2f, float metal = 0f, Color? emission = null)
    {
        Material m;
        if (mats.TryGetValue(name, out m)) return m;
        string path = Root + "/Materials/" + name + ".mat";
        Shader sh = IsUrp() ? Shader.Find("Universal Render Pipeline/Lit") : Shader.Find("Standard");
        m = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (m == null) { m = new Material(sh); AssetDatabase.CreateAsset(m, path); }
        else m.shader = sh;
        m.color = c;
        if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
        if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smooth);
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smooth);
        if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", metal);
        if (emission.HasValue)
        {
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission.Value);
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        }
        EditorUtility.SetDirty(m);
        mats[name] = m;
        return m;
    }

    static Material FloorMaterial()
    {
        string texPath = Root + "/Materials/FloorChecker.asset";
        var tex = AssetDatabase.LoadAssetAtPath<Texture2D>(texPath);
        if (tex == null)
        {
            tex = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat };
            Color a = new Color(0.27f, 0.28f, 0.31f), b = new Color(0.33f, 0.34f, 0.37f);
            tex.SetPixels(new[] { a, b, b, a });
            tex.Apply();
            AssetDatabase.CreateAsset(tex, texPath);
        }
        var m = Mat("Floor", Color.white, 0.45f);
        m.mainTexture = tex;
        m.mainTextureScale = new Vector2(10f, 6.25f); // клетка 48 см
        if (m.HasProperty("_BaseMap")) { m.SetTexture("_BaseMap", tex); m.SetTextureScale("_BaseMap", new Vector2(10f, 6.25f)); }
        EditorUtility.SetDirty(m);
        return m;
    }

    static Material ConeMaterial()
    {
        string path = Root + "/Materials/VisionCone.mat";
        var m = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (m == null)
        {
            var sh = Shader.Find("Sprites/Default");
            if (sh == null) sh = Shader.Find("Universal Render Pipeline/Unlit");
            if (sh == null) sh = Shader.Find("Unlit/Color");
            m = new Material(sh);
            AssetDatabase.CreateAsset(m, path);
        }
        m.color = new Color(0.86f, 0.86f, 0.92f, 0.14f);
        EditorUtility.SetDirty(m);
        return m;
    }

    static void EnsureFolder(string path)
    {
        if (AssetDatabase.IsValidFolder(path)) return;
        int slash = path.LastIndexOf('/');
        string parent = path.Substring(0, slash), name = path.Substring(slash + 1);
        EnsureFolder(parent);
        AssetDatabase.CreateFolder(parent, name);
    }
}
