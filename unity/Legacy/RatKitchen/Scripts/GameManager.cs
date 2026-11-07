using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public enum GameState { Menu, Intro, Play, Pause, Outro, Over }

/// <summary>
/// Главный скрипт: правила ночи, еда, жизни, кат-сцены (пробуждение и финал) и интерфейс.
/// Интерфейс нарисован через OnGUI, чтобы проект запускался без лишних пакетов.
/// Позже его стоит заменить на Canvas + TextMeshPro или UI Toolkit.
/// </summary>
public class GameManager : MonoBehaviour
{
    public static GameManager I { get; private set; }

    [Header("Правила")]
    public int goal = 15;
    [Tooltip("Длина ночи в секундах (23:00 → 05:00)")] public float nightLength = 240f;
    public int maxCarry = 3;
    public int startLives = 3;
    public int itemsOnFloor = 6;
    [Range(0f, 1f)] public float cheeseChance = 0.22f;

    [Header("Ссылки на сцену")]
    public RatController rat;
    public CatAI cat;
    public ThirdPersonCamera cam;
    public Transform hole;
    public float holeRadius = 0.3f;
    public Transform kitchenSpawn;
    public Transform nestCenter;
    public Transform motherSleep;
    public Transform pileCenter;
    public Transform[] introPath;
    public Pup[] pups;
    public FoodItem crumbTemplate;
    public FoodItem cheeseTemplate;
    [Tooltip("Где на кухне может появляться еда (X и Z, метры)")]
    public Vector2 spawnMin = new Vector2(0.9f, 0.2f);
    public Vector2 spawnMax = new Vector2(9.3f, 5.1f);

    public GameState State { get; private set; }
    public readonly List<FoodItem> items = new List<FoodItem>();
    readonly List<FoodItem> pile = new List<FoodItem>();

    int fed, lives;
    float night, bestTime;
    bool skipRequested;
    float fade, fadeTarget, bars, barsTarget;
    string bannerTitle, bannerSub;
    float bannerTime;
    bool overlayOn;
    string ovTitle, ovText, ovButton;

    class Msg { public Vector3 pos; public string text; public float t; public bool bubble; public Color col; }
    readonly List<Msg> msgs = new List<Msg>();

    static readonly Color Yellow = new Color(0.95f, 0.76f, 0.31f);
    static readonly Color Red = new Color(0.91f, 0.4f, 0.29f);
    static readonly Color Green = new Color(0.61f, 0.88f, 0.42f);
    static readonly Color Ink = new Color(0.93f, 0.9f, 0.85f);

    // ───────────────────────── жизненный цикл ─────────────────────────

    void Awake()
    {
        I = this;
        bestTime = PlayerPrefs.GetFloat("ratBestTime", 0f);
    }

    void Start()
    {
        foreach (var b in CatBlocker.All)
            if (b) Physics.IgnoreCollision(rat.Cc, b, true);
        crumbTemplate.gameObject.SetActive(false);
        cheeseTemplate.gameObject.SetActive(false);
        cam.target = rat.transform;
        ShowMenu();
    }

    void Update()
    {
        float dt = Time.deltaTime;
        fade = Mathf.MoveTowards(fade, fadeTarget, dt * 2f);
        bars = Mathf.MoveTowards(bars, barsTarget, dt * 2f);
        bannerTime -= dt;
        for (int i = msgs.Count - 1; i >= 0; i--)
        {
            var m = msgs[i];
            m.t -= dt;
            m.pos += Vector3.up * dt * (m.bubble ? 0.04f : 0.2f);
            if (m.t <= 0f) msgs.RemoveAt(i);
        }

        switch (State)
        {
            case GameState.Menu:
                float a = Time.time * 0.08f;
                cam.scriptedPos = new Vector3(4.8f + Mathf.Cos(a) * 4.2f, 1.7f, 3f + Mathf.Sin(a) * 2.6f);
                cam.scriptedLook = new Vector3(4.8f, 0.2f, 3f);
                break;
            case GameState.Intro:
                if (GameInput.SkipPressed()) skipRequested = true;
                break;
            case GameState.Play:
                TickPlay(dt);
                break;
            case GameState.Pause:
                if (GameInput.PausePressed()) Resume();
                break;
        }
    }

    void OnApplicationFocus(bool focus)
    {
        if (!focus && State == GameState.Play) Pause();
    }

    // ───────────────────────── состояние игры ─────────────────────────

    void ShowMenu()
    {
        State = GameState.Menu;
        UnlockCursor();
        cam.scripted = true;
        rat.Teleport(motherSleep.position, motherSleep.eulerAngles.y, false);
        rat.wake = 0f;
        cat.ResetCat();
        ShowOverlay("Крыса на кухне",
            "В норе за стеной ждут голодные крысята. Пока хозяева спят, добудь им " + goal +
            " еды до рассвета и не попадись коту.", "Играть");
    }

    void ResetRun()
    {
        StopAllCoroutines();
        foreach (var f in items) if (f) Destroy(f.gameObject);
        items.Clear();
        foreach (var f in pile) if (f) Destroy(f.gameObject);
        pile.Clear();
        foreach (var f in rat.carried) if (f) Destroy(f.gameObject);
        rat.carried.Clear();
        msgs.Clear();
        fed = 0; lives = startLives; night = 0f;
        foreach (var p in pups) p.eating = false;
        cat.ResetCat();
        for (int i = 0; i < itemsOnFloor; i++) SpawnItem();
    }

    void Pause()
    {
        State = GameState.Pause;
        UnlockCursor();
        ShowOverlay("Пауза", "Крысята ждут. Кот тоже.", "Продолжить");
    }

    void Resume()
    {
        State = GameState.Play;
        overlayOn = false;
        LockCursor();
    }

    void Lose(string title, string text)
    {
        State = GameState.Over;
        cam.inputEnabled = false;
        UnlockCursor();
        ShowOverlay(title, text, "Попробовать снова");
    }

    void OnOverlayButton()
    {
        if (State == GameState.Pause) { Resume(); return; }
        ResetRun();
        StartCoroutine(IntroRoutine());
    }

    void ShowOverlay(string t, string text, string button)
    {
        ovTitle = t; ovText = text; ovButton = button; overlayOn = true;
    }

    static void LockCursor() { Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }
    static void UnlockCursor() { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }

    // ───────────────────────── геймплей ─────────────────────────

    void TickPlay(float dt)
    {
        night += dt;
        if (night >= nightLength)
        {
            Lose("Рассвет", "Хозяева просыпаются, а крысята получили " + fed + " из " + goal + ". Завтра будет новая ночь.");
            return;
        }
        if (GameInput.PausePressed()) { Pause(); return; }
        if (GameInput.ClickPressed() && Cursor.lockState != CursorLockMode.Locked) LockCursor();

        rat.Tick(dt, cam.FlatForward);

        // подобрать еду
        for (int i = items.Count - 1; i >= 0; i--)
        {
            var f = items[i];
            if (Sight.FlatDistance(f.transform.position, rat.transform.position) < rat.pickupRadius &&
                rat.CarryWeight + f.weight <= maxCarry)
            {
                items.RemoveAt(i);
                f.carried = true;
                f.transform.SetParent(rat.mouth, false);
                rat.carried.Add(f);
            }
        }

        // отнести в нору
        if (rat.carried.Count > 0 && Sight.FlatDistance(rat.transform.position, hole.position) < holeRadius + 0.06f)
        {
            int v = 0, n = rat.carried.Count;
            foreach (var f in rat.carried) { v += f.value; AddToPile(f); }
            rat.carried.Clear();
            fed += v;
            for (int i = 0; i < n; i++) SpawnItem();
            if (fed >= goal) { StartCoroutine(OutroRoutine()); return; }
            Say(hole.position + Vector3.up * 0.32f, "+" + v, 1.4f, false, Yellow);
            int left = goal - fed;
            Say(hole.position + Vector3.up * 0.2f, left > 8 ? "Пи! Ещё хотим!" : left > 3 ? "Почти наелись!" : "Ещё чуть-чуть!", 1.8f, true, Ink);
        }

        // кот
        if (cat.Tick(dt, rat))
        {
            lives--;
            foreach (var f in rat.carried)
            {
                Vector3 p = rat.transform.position + new Vector3(Random.Range(-0.15f, 0.15f), 0f, Random.Range(-0.15f, 0.15f));
                p.y = 0.035f;
                f.PlaceOnFloor(p);
                items.Add(f);
            }
            rat.carried.Clear();
            Say(cat.transform.position + Vector3.up * 0.55f, "Поймал!", 1.4f, false, Red);
            rat.Teleport(kitchenSpawn.position, kitchenSpawn.eulerAngles.y);
            cam.yaw = kitchenSpawn.eulerAngles.y;
            cat.AfterCatch();
            if (lives <= 0)
                Lose("Кот поймал тебя", "Крысята получили " + fed + " из " + goal + " и ждут маму. Попробуй ещё раз.");
        }
    }

    public void OnRatNoise(Vector3 pos) { cat.Hear(pos); }

    public bool InHole(Vector3 p) { return Sight.FlatDistance(p, hole.position) < holeRadius; }

    void SpawnItem()
    {
        for (int t = 0; t < 200; t++)
        {
            float x = Random.Range(spawnMin.x, spawnMax.x), z = Random.Range(spawnMin.y, spawnMax.y);
            Vector3 p = new Vector3(x, 0.035f, z);
            if (Sight.FlatDistance(p, hole.position) < 1.2f) continue;
            if (Physics.CheckSphere(new Vector3(x, 0.25f, z), 0.2f, ~0, QueryTriggerInteraction.Collide)) continue;
            var tpl = Random.value < cheeseChance ? cheeseTemplate : crumbTemplate;
            var f = Instantiate(tpl);
            f.gameObject.SetActive(true);
            f.PlaceOnFloor(p);
            items.Add(f);
            return;
        }
    }

    void AddToPile(FoodItem f)
    {
        f.transform.SetParent(null);
        f.carried = true;
        Vector2 r = Random.insideUnitCircle * 0.14f;
        f.transform.position = pileCenter.position + new Vector3(r.x, 0.03f + pile.Count * 0.0015f, r.y);
        f.transform.rotation = Quaternion.Euler(0f, Random.Range(0f, 360f), 0f);
        pile.Add(f);
    }

    // ───────────────────────── кат-сцены ─────────────────────────

    IEnumerator IntroRoutine()
    {
        State = GameState.Intro;
        overlayOn = false;
        skipRequested = false;
        barsTarget = 1f; fadeTarget = 0f;
        UnlockCursor();

        rat.Teleport(motherSleep.position, motherSleep.eulerAngles.y, false);
        rat.wake = 0f;
        cam.scripted = true;
        cam.scriptedSharpness = 3f;
        Vector3 nc = nestCenter.position;
        cam.transform.position = nc + new Vector3(0.9f, 0.45f, 0.7f);

        string[] lines = { "Пи!", "Мама, есть хотим!", "Пи-пи-пи!", "Очень-очень хотим!" };
        int[] who = { 0, 1, 3, 2 };
        float[] at = { 0.7f, 1.5f, 2.3f, 3.1f };
        int next = 0;
        bool momSaid = false;
        float t = 0f;

        // крысята пищат, мама просыпается
        while (!skipRequested && t < 5.2f)
        {
            t += Time.deltaTime;
            while (next < lines.Length && t >= at[next])
            {
                Say(pups[who[next] % pups.Length].transform.position + Vector3.up * 0.2f, lines[next], 1.8f, true, Ink);
                next++;
            }
            if (!momSaid && t >= 4.2f)
            {
                momSaid = true;
                Say(rat.transform.position + Vector3.up * 0.3f, "Тише, тише. Сейчас что-нибудь принесу.", 2.6f, true, Ink);
            }
            rat.wake = t < 3.6f ? 0f : Mathf.SmoothStep(0f, 1f, (t - 3.6f) / 1.2f);
            float a = 0.5f + t * 0.09f, r = Mathf.Lerp(0.95f, 0.7f, t / 5f);
            cam.scriptedPos = nc + new Vector3(Mathf.Cos(a) * r, Mathf.Lerp(0.5f, 0.32f, t / 5f), Mathf.Sin(a) * r * 0.7f);
            cam.scriptedLook = nc + Vector3.up * 0.08f;
            yield return null;
        }
        rat.wake = 1f;

        // мама идёт к выходу из норы, камера следует сзади
        cam.scripted = false;
        cam.inputEnabled = false;
        cam.pitch = 23f;
        cam.yaw = rat.transform.eulerAngles.y;
        for (int i = 0; i < introPath.Length && !skipRequested; i++)
        {
            Vector3 tgt = introPath[i].position;
            while (!skipRequested)
            {
                Vector3 d = tgt - rat.transform.position; d.y = 0f;
                if (d.magnitude < 0.04f) break;
                rat.transform.rotation = Quaternion.Slerp(rat.transform.rotation, Quaternion.LookRotation(d), Time.deltaTime * 8f);
                rat.transform.position += d.normalized * 0.8f * Time.deltaTime;
                rat.ScriptedStep(Time.deltaTime * 12f);
                cam.yaw = Mathf.LerpAngle(cam.yaw, rat.transform.eulerAngles.y, Time.deltaTime * 4f);
                yield return null;
            }
        }

        fadeTarget = 1f;
        yield return new WaitForSeconds(0.55f);
        BeginPlay();
    }

    void BeginPlay()
    {
        msgs.Clear();
        rat.Teleport(kitchenSpawn.position, kitchenSpawn.eulerAngles.y);
        rat.wake = 1f;
        cam.scripted = false;
        cam.inputEnabled = true;
        cam.yaw = kitchenSpawn.eulerAngles.y;
        cam.pitch = 22f;
        cam.SnapNow();
        State = GameState.Play;
        barsTarget = 0f; fadeTarget = 0f;
        bannerTitle = "Накорми крысят";
        bannerSub = "Принеси " + goal + " еды до рассвета";
        bannerTime = 3.5f;
        LockCursor();
    }

    IEnumerator OutroRoutine()
    {
        State = GameState.Outro;
        cam.inputEnabled = false;
        UnlockCursor();
        fadeTarget = 1f; barsTarget = 1f;
        yield return new WaitForSeconds(0.55f);

        msgs.Clear();
        rat.Teleport(motherSleep.position, motherSleep.eulerAngles.y, false);
        rat.wake = 1f;
        Vector3 pc = pileCenter.position;
        for (int i = 0; i < pups.Length; i++)
        {
            float ang = i / (float)pups.Length * Mathf.PI * 2f;
            Vector3 pos = pc + new Vector3(Mathf.Cos(ang), 0f, Mathf.Sin(ang)) * 0.17f;
            pos.y = 0f;
            pups[i].eatPos = pos;
            pups[i].eatYaw = Quaternion.LookRotation(new Vector3(pc.x - pos.x, 0f, pc.z - pos.z)).eulerAngles.y;
            pups[i].eating = true;
        }
        Vector3 nc = nestCenter.position;
        cam.scripted = true;
        cam.scriptedSharpness = 2.5f;
        cam.transform.position = nc + new Vector3(0.8f, 0.4f, 0.6f);
        fadeTarget = 0f;

        string[] lines = { "Ням!", "Спасибо, мама!", "Ням-ням-ням!", "Я наелся!" };
        float[] at = { 0.6f, 1.3f, 2.1f, 3f };
        int next = 0;
        float t = 0f;
        while (t < 4.6f)
        {
            t += Time.deltaTime;
            while (next < lines.Length && t >= at[next])
            {
                Say(pups[next % pups.Length].transform.position + Vector3.up * 0.2f, lines[next], 1.8f, true, Ink);
                next++;
            }
            float a = 0.4f + t * 0.12f;
            cam.scriptedPos = nc + new Vector3(0.1f + Mathf.Cos(a) * 0.8f, 0.36f, Mathf.Sin(a) * 0.6f);
            cam.scriptedLook = pc + Vector3.up * 0.06f;
            yield return null;
        }

        bool record = bestTime <= 0f || night < bestTime;
        if (record) { bestTime = night; PlayerPrefs.SetFloat("ratBestTime", bestTime); PlayerPrefs.Save(); }
        State = GameState.Over;
        barsTarget = 0f;
        ShowOverlay("Крысята сыты",
            "Ты успела к " + Clock(night) + ", потратив жизней: " + (startLives - lives) + ". " +
            (record ? "Это новый рекорд!" : "Лучшее время: " + Clock(bestTime) + "."),
            "Ещё одна ночь");
    }

    // ───────────────────────── интерфейс ─────────────────────────

    public void Say(Vector3 worldPos, string text, float duration, bool bubble, Color color)
    {
        msgs.Add(new Msg { pos = worldPos, text = text, t = duration, bubble = bubble, col = color });
    }

    string Clock(float t)
    {
        int mins = 23 * 60 + Mathf.FloorToInt(t / nightLength * 360f);
        return ((mins / 60) % 24).ToString("00") + ":" + (mins % 60).ToString("00");
    }

    GUIStyle sLabel, sTitle, sText, sBubble, sButton, sTag, sBanner;
    Texture2D bubbleTex;
    float guiScale = 1f;

    void EnsureStyles()
    {
        if (sLabel != null) return;
        sLabel = new GUIStyle(GUI.skin.label) { fontSize = 18, fontStyle = FontStyle.Bold };
        sLabel.normal.textColor = Ink;
        sTitle = new GUIStyle(sLabel) { fontSize = 40, alignment = TextAnchor.MiddleCenter };
        sBanner = new GUIStyle(sLabel) { fontSize = 32, alignment = TextAnchor.MiddleCenter };
        sText = new GUIStyle(sLabel) { fontSize = 19, fontStyle = FontStyle.Normal, alignment = TextAnchor.MiddleCenter, wordWrap = true };
        sTag = new GUIStyle(sLabel) { fontSize = 30, alignment = TextAnchor.MiddleCenter };
        bubbleTex = new Texture2D(1, 1);
        bubbleTex.SetPixel(0, 0, new Color(0.96f, 0.94f, 0.89f));
        bubbleTex.Apply();
        sBubble = new GUIStyle(GUI.skin.box) { fontSize = 16, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter, padding = new RectOffset(12, 12, 7, 7) };
        sBubble.normal.background = bubbleTex;
        sBubble.normal.textColor = new Color(0.11f, 0.1f, 0.09f);
        sButton = new GUIStyle(GUI.skin.button) { fontSize = 20, fontStyle = FontStyle.Bold };
    }

    static void Rect(Rect r, Color c)
    {
        var old = GUI.color;
        GUI.color = c;
        GUI.DrawTexture(r, Texture2D.whiteTexture);
        GUI.color = old;
    }

    void Shadowed(Rect r, string text, GUIStyle style, Color color)
    {
        var old = style.normal.textColor;
        style.normal.textColor = new Color(0f, 0f, 0f, 0.7f * color.a);
        GUI.Label(new Rect(r.x + 2, r.y + 2, r.width, r.height), text, style);
        style.normal.textColor = color;
        GUI.Label(r, text, style);
        style.normal.textColor = old;
    }

    bool ToGui(Vector3 world, out Vector2 g)
    {
        Vector3 sp = Camera.main ? Camera.main.WorldToScreenPoint(world) : Vector3.back;
        g = new Vector2(sp.x / guiScale, (Screen.height - sp.y) / guiScale);
        return sp.z > 0f;
    }

    void OnGUI()
    {
        EnsureStyles();
        guiScale = Screen.height / 720f;
        GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(guiScale, guiScale, 1f));
        float vw = Screen.width / guiScale, vh = 720f;
        bool inRun = State == GameState.Play || State == GameState.Pause;

        // реплики и всплывающие числа
        foreach (var m in msgs)
        {
            Vector2 g;
            if (!ToGui(m.pos, out g)) continue;
            float alpha = Mathf.Clamp01(m.t * 2f);
            if (m.bubble)
            {
                var c = new GUIContent(m.text);
                Vector2 size = sBubble.CalcSize(c);
                var old = GUI.color; GUI.color = new Color(1f, 1f, 1f, alpha);
                GUI.Box(new Rect(g.x - size.x / 2f, g.y - size.y, size.x, size.y), c, sBubble);
                GUI.color = old;
            }
            else
            {
                var col = m.col; col.a = alpha;
                Shadowed(new Rect(g.x - 100, g.y - 40, 200, 40), m.text, sTag, col);
            }
        }

        // значок над котом
        if (inRun && (cat.CurrentMode != CatAI.Mode.Patrol || cat.Alert > 0.05f))
        {
            Vector2 g;
            if (ToGui(cat.transform.position + Vector3.up * 0.6f, out g))
            {
                string s; Color c;
                if (cat.CurrentMode == CatAI.Mode.Chase) { s = "!"; c = Red; }
                else if (cat.CurrentMode == CatAI.Mode.Patrol) { s = new string('•', Mathf.CeilToInt(cat.Alert * 5f)); c = Yellow; }
                else { s = "?"; c = Yellow; }
                Shadowed(new Rect(g.x - 60, g.y - 40, 120, 40), s, sTag, c);
            }
        }

        // верхняя панель
        if (inRun || State == GameState.Over)
        {
            Rect(new Rect(0, 0, vw, 44), new Color(0f, 0f, 0f, 0.45f));
            GUI.Label(new Rect(16, 10, 260, 30), "Крысята сыты: " + Mathf.Min(fed, goal) + " / " + goal, sLabel);
            GUI.Label(new Rect(270, 10, 180, 30), "В зубах: " + (rat ? rat.CarryWeight : 0) + " / " + maxCarry, sLabel);
            GUI.Label(new Rect(440, 10, 150, 30), "Жизни: " + lives, sLabel);
            GUI.Label(new Rect(580, 10, 260, 30), "Время: " + Clock(night) + " (рассвет в 05:00)", sLabel);
        }

        if (State == GameState.Play)
        {
            string st; Color sc;
            if (rat.Hidden) { st = "Спрятался"; sc = Green; }
            else if (cat.SeesRat) { st = "Кот тебя видит!"; sc = Red; }
            else { st = "Тебя не видно"; sc = Ink; }
            Shadowed(new Rect(16, 52, 300, 28), st, sLabel, sc);

            if (rat.carried.Count > 0)
            {
                Vector3 toHole = hole.position - rat.transform.position; toHole.y = 0f;
                float dist = toHole.magnitude;
                if (dist > 0.6f)
                {
                    float ang = Vector3.SignedAngle(cam.FlatForward, toHole, Vector3.up);
                    string dir = Mathf.Abs(ang) < 30f ? "прямо" : Mathf.Abs(ang) > 150f ? "сзади" : ang > 0f ? "справа" : "слева";
                    var sl = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter };
                    Shadowed(new Rect(vw / 2 - 200, vh - 50, 400, 30), "К крысятам: " + dist.ToString("0.0") + " м, " + dir, sl, Yellow);
                }
            }

            if (Cursor.lockState != CursorLockMode.Locked)
            {
                var sl = new GUIStyle(sLabel) { fontSize = 15, alignment = TextAnchor.MiddleRight };
                Shadowed(new Rect(vw - 520, 52, 504, 26), "Кликни по игре, чтобы управлять камерой мышью", sl, Ink);
            }
            else
            {
                Rect(new Rect(vw / 2 - 2, vh / 2 - 2, 4, 4), new Color(1f, 1f, 1f, 0.5f));
            }
        }

        if (bannerTime > 0f)
        {
            float a = Mathf.Clamp01(bannerTime / 0.6f);
            Shadowed(new Rect(0, vh * 0.2f, vw, 44), bannerTitle, sBanner, new Color(Ink.r, Ink.g, Ink.b, a));
            var ss = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter };
            Shadowed(new Rect(0, vh * 0.2f + 46, vw, 30), bannerSub, ss, new Color(Yellow.r, Yellow.g, Yellow.b, a));
        }

        // кинематографичные полосы
        float bh = bars * vh * 0.11f;
        if (bh > 0.5f)
        {
            Rect(new Rect(0, 0, vw, bh), Color.black);
            Rect(new Rect(0, vh - bh, vw, bh), Color.black);
        }
        if (State == GameState.Intro && GUI.Button(new Rect(vw - 230, vh - bh - 50, 210, 38), "Пропустить (Пробел)", sButton))
            skipRequested = true;

        if (fade > 0.001f) Rect(new Rect(0, 0, vw, vh), new Color(0f, 0f, 0f, fade));

        if (overlayOn)
        {
            Rect(new Rect(0, 0, vw, vh), new Color(0.05f, 0.06f, 0.07f, 0.8f));
            Shadowed(new Rect(0, vh / 2 - 120, vw, 60), ovTitle, sTitle, Ink);
            GUI.Label(new Rect(vw / 2 - 300, vh / 2 - 55, 600, 100), ovText, sText);
            if (GUI.Button(new Rect(vw / 2 - 120, vh / 2 + 65, 240, 50), ovButton, sButton))
                OnOverlayButton();
        }
    }
}
