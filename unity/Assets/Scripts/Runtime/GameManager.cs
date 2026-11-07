using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace KitchenRat
{
    /// <summary>
    /// One night: food pickup and delivery, zones, pushing things off, sniffing, the clock, tasks and the HUD.
    /// The HUD uses IMGUI so the skeleton has no UI assets; replace it with uGUI / UI Toolkit later.
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }

        public string nightId = "kitchen";
        public RatController rat;
        public GameObject crumbModel, cheeseModel;
        [Tooltip("Scale applied to spawned models (set by the scene builder if the FBX units differ).")]
        public float unitScale = 1f;

        public NightDef Night { get; private set; }
        public TaskTracker Tasks { get; private set; }
        public int NestCount { get; private set; }

        enum State { Intro, Play, Pause, Won, Lost }
        State state = State.Intro;
        float time;
        float sniffT;
        bool sniffedFlag;
        readonly List<Food> foods = new List<Food>();
        Zone[] zones;
        Knockable[] knockables;
        LineRenderer trail;
        readonly List<(string text, float t)> toasts = new List<(string, float)>();

        void Awake()
        {
            I = this;
            Night = Nights.Get(nightId);
            Tasks = new TaskTracker(Night);
            Tasks.Completed += t => Toast("✓ " + t);
            Tasks.Failed += t => Toast("✗ " + t);
        }

        void Start()
        {
            foods.AddRange(FindObjectsByType<Food>(FindObjectsSortMode.None));
            zones = FindObjectsByType<Zone>(FindObjectsSortMode.None);
            knockables = FindObjectsByType<Knockable>(FindObjectsSortMode.None);
            SpawnRandomFood(crumbModel, FoodKind.Crumb, Night.randomCrumbs);
            SpawnRandomFood(cheeseModel, FoodKind.Cheese, Night.randomCheese);
            rat.SurfaceChanged += id => Report(Check.Surf, id);
            rat.Frozen = true;
            MakeTrail();
        }

        // ---------- events from the world ----------

        public void Report(Check c, string arg) { if (state == State.Play) Tasks.Report(c, arg); }

        public void Toast(string text)
        {
            toasts.RemoveAll(t => t.text == text);
            toasts.Add((text, 3f));
            if (toasts.Count > 3) toasts.RemoveAt(0);
        }

        public void Noise(Vector3 at, float loudness, string label)
        {
            rat.AddNoise(Vector3.Distance(at, rat.transform.position) < 3f ? loudness : loudness * 0.5f);
            if (!string.IsNullOrEmpty(label)) Toast(label);
        }

        public void Deliver()
        {
            int n = rat.carried.Count, value = 0;
            foreach (var f in rat.carried)
            {
                value += f.Value;
                Report(Check.Deliver, f.id);
                foods.Remove(f);
                Destroy(f.gameObject);
            }
            rat.carried.Clear();
            NestCount += value;
            if (value > 0) Toast("+" + value + " for the nest");
            if (n >= 3) Report(Check.Flag, "full");
            if (NestCount >= Night.goal) EndNight(true);
        }

        // ---------- loop ----------

        void Update()
        {
            float dt = Time.deltaTime;
            for (int i = toasts.Count - 1; i >= 0; i--)
            {
                var t = toasts[i];
                t.t -= Time.unscaledDeltaTime;
                if (t.t <= 0f) toasts.RemoveAt(i); else toasts[i] = t;
            }

            switch (state)
            {
                case State.Intro:
                    if (GameInput.Click || GameInput.Jump) Begin();
                    return;
                case State.Pause:
                    if (GameInput.Pause || GameInput.Click) SetPaused(false);
                    if (GameInput.Restart) Restart();
                    return;
                case State.Won:
                case State.Lost:
                    if (GameInput.Restart || GameInput.Click) Restart();
                    return;
            }

            if (GameInput.Pause) { SetPaused(true); return; }
            time += dt;
            if (time >= Night.seconds) { EndNight(false); return; }

            Vector3 rp = rat.transform.position;
            PickUp(rp);
            TickZones(rp, dt);
            TickKnockables(rp);
            TickSniff(dt);
        }

        void PickUp(Vector3 rp)
        {
            if (rat.Jumping) return;
            foreach (var f in foods)
            {
                if (f.carried || f.hidden) continue;
                Vector3 d = f.transform.position - rp;
                if (Mathf.Abs(d.y) > 0.15f || new Vector2(d.x, d.z).magnitude > 0.16f) continue;
                if (f.kind == FoodKind.Find)
                {
                    Toast(string.IsNullOrEmpty(f.label) ? "A find for the nest!" : f.label);
                    Report(Check.Pick, f.id);
                    if (!string.IsNullOrEmpty(f.flag)) Report(Check.Flag, f.flag);
                    foods.Remove(f);
                    Destroy(f.gameObject);
                    return;
                }
                if (rat.carried.Count >= rat.capacity)
                {
                    Toast("Your mouth is full. Take it home first.");
                    return;
                }
                rat.Carry(f);
                Report(Check.Pick, f.id);
                return; // one per frame
            }
        }

        void TickZones(Vector3 rp, float dt)
        {
            foreach (var z in zones)
            {
                bool inside = z.Contains(rp);
                if (inside && !z.inside) z.Enter(rat);
                if (!inside && z.inside) z.Exit(rat);
                z.inside = inside;
                if (inside) z.Stay(rat, dt);
            }
        }

        void TickKnockables(Vector3 rp)
        {
            bool push = GameInput.Push;
            foreach (var k in knockables)
            {
                if (k.knocked) continue;
                Vector3 d = k.transform.position - rp;
                if (Mathf.Abs(d.y) > 0.2f) continue;
                float dist = new Vector2(d.x, d.z).magnitude;
                if (k.trap && dist < 0.16f && rat.Moving && !rat.Sneaking)
                {
                    k.Knock(k.pushDir);
                    Toast("Oops! The " + k.kind + " fell. Sneak past things on the edge.");
                }
                else if (push && dist < 0.28f && Vector3.Dot(rat.transform.forward, new Vector3(d.x, 0, d.z).normalized) > 0.3f)
                {
                    k.Knock(rat.transform.forward);
                    push = false;
                }
            }
        }

        void TickSniff(float dt)
        {
            if (!rat.Sniffing)
            {
                sniffT = 0f;
                trail.enabled = false;
                return;
            }
            sniffT += dt;
            if (sniffT > 0.5f && !sniffedFlag) { sniffedFlag = true; Report(Check.Flag, "sniffed"); }
            Food best = null;
            float bestD = float.MaxValue;
            Vector3 rp = rat.transform.position;
            foreach (var f in foods)
            {
                if (f.carried) continue;
                float d = Vector3.Distance(f.transform.position, rp);
                if (f.hidden && d < 1.5f && sniffT > 0.4f) { f.Reveal(); Toast("You smell something hidden here!"); }
                if (f.kind != FoodKind.Find && d < bestD) { bestD = d; best = f; }
            }
            trail.enabled = best != null && sniffT > 0.2f;
            if (!trail.enabled) return;
            Vector3 a = (rat.mouth ? rat.mouth.position : rp) + Vector3.up * 0.05f, b = best.transform.position + Vector3.up * 0.03f;
            int count = trail.positionCount;
            for (int i = 0; i < count; i++)
            {
                float t = i / (count - 1f);
                Vector3 p = Vector3.Lerp(a, b, t);
                p += Vector3.up * Mathf.Sin(t * Mathf.PI) * 0.15f + Vector3.Cross(b - a, Vector3.up).normalized * Mathf.Sin(t * 12f + Time.time * 3f) * 0.02f;
                trail.SetPosition(i, p);
            }
            float alpha = Mathf.Clamp01((sniffT - 0.2f) * 2f) * (0.55f + 0.25f * Mathf.Sin(Time.time * 5f));
            var c = new Color(1f, 0.85f, 0.5f, alpha);
            trail.startColor = c;
            trail.endColor = new Color(c.r, c.g, c.b, alpha * 0.4f);
        }

        // ---------- setup ----------

        void SpawnRandomFood(GameObject model, FoodKind kind, int count)
        {
            if (!model) return;
            int placed = 0;
            for (int tries = 0; placed < count && tries < count * 40; tries++)
            {
                Vector3 p = Nights.World(Random.Range(30f, Night.width - 30f), Random.Range(30f, Night.depth - 30f), 230f, Night.width, Night.depth);
                if (!Physics.Raycast(p, Vector3.down, out var hit, 3f, RatController.Mask, QueryTriggerInteraction.Ignore)) continue;
                if (hit.normal.y < 0.8f || hit.point.y > 1.0f || hit.collider.GetComponentInParent<Knockable>()) continue; // nothing on top of the fridge
                if (Physics.CheckSphere(hit.point + Vector3.up * 0.08f, 0.05f, RatController.Mask, QueryTriggerInteraction.Ignore)) continue;
                var go = Instantiate(model, hit.point, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
                go.transform.localScale *= unitScale;
                var f = go.AddComponent<Food>();
                f.kind = kind;
                foods.Add(f);
                placed++;
            }
        }

        void MakeTrail()
        {
            trail = new GameObject("Scent trail").AddComponent<LineRenderer>();
            trail.positionCount = 24;
            trail.widthMultiplier = 0.008f;
            trail.material = new Material(Shader.Find("Sprites/Default"));
            trail.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            trail.enabled = false;
        }

        // ---------- states ----------

        void Begin()
        {
            state = State.Play;
            rat.Frozen = false;
            LockCursor(true);
        }

        void SetPaused(bool on)
        {
            state = on ? State.Pause : State.Play;
            Time.timeScale = on ? 0f : 1f;
            rat.Frozen = on;
            LockCursor(!on);
        }

        void EndNight(bool won)
        {
            Tasks.FinishNight();
            state = won ? State.Won : State.Lost;
            rat.Frozen = true;
            LockCursor(false);
        }

        void Restart()
        {
            Time.timeScale = 1f;
            SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
        }

        static void LockCursor(bool on)
        {
            Cursor.lockState = on ? CursorLockMode.Locked : CursorLockMode.None;
            Cursor.visible = !on;
        }

        void OnApplicationFocus(bool focus)
        {
            if (!focus && state == State.Play) SetPaused(true);
        }

        // ---------- HUD ----------

        GUIStyle big, mid, small, hint, center;
        Texture2D panel, barBg, barFill, noiseFill;

        static Texture2D Tex(Color c)
        {
            var t = new Texture2D(1, 1);
            t.SetPixel(0, 0, c);
            t.Apply();
            return t;
        }

        void Styles()
        {
            if (big != null) return;
            big = new GUIStyle(GUI.skin.label) { fontSize = 34, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter, wordWrap = true };
            mid = new GUIStyle(GUI.skin.label) { fontSize = 17, fontStyle = FontStyle.Bold, wordWrap = true };
            small = new GUIStyle(GUI.skin.label) { fontSize = 14, wordWrap = true };
            hint = new GUIStyle(small) { fontSize = 13, fontStyle = FontStyle.Italic };
            hint.normal.textColor = new Color(0.85f, 0.85f, 0.75f);
            center = new GUIStyle(small) { fontSize = 16, alignment = TextAnchor.MiddleCenter };
            panel = Tex(new Color(0.05f, 0.06f, 0.1f, 0.72f));
            barBg = Tex(new Color(1f, 1f, 1f, 0.15f));
            barFill = Tex(new Color(1f, 0.72f, 0.35f, 0.95f));
            noiseFill = Tex(new Color(1f, 0.35f, 0.3f, 0.9f));
        }

        string Clock()
        {
            float h = 23f + 7f * Mathf.Clamp01(time / Night.seconds);
            int hh = (int)h % 24, mm = (int)((h - Mathf.Floor(h)) * 60f);
            return hh.ToString("00") + ":" + mm.ToString("00");
        }

        void OnGUI()
        {
            Styles();
            float s = Screen.height / 720f;
            GUI.matrix = Matrix4x4.Scale(new Vector3(s, s, 1f));
            float W = Screen.width / s, H = 720f;

            if (state == State.Intro)
            {
                GUI.DrawTexture(new Rect(0, 0, W, H), panel);
                GUI.Label(new Rect(0, H * 0.28f, W, 50), "Night " + Night.number + " · " + Night.name, big);
                GUI.Label(new Rect(W / 2 - 300, H * 0.28f + 60, 600, 30), Night.startTitle, center);
                GUI.Label(new Rect(W / 2 - 300, H * 0.28f + 90, 600, 50), Night.startSub, center);
                GUI.Label(new Rect(W / 2 - 360, H * 0.62f, 720, 60),
                    "WASD move · Mouse look · Shift run · Ctrl or C sneak · Space jump (aim at the yellow ring) · E or right mouse sniff · F push · Esc pause", center);
                GUI.Label(new Rect(0, H * 0.75f, W, 40), "Click to start", big);
                return;
            }

            // top-left: night and clock
            GUI.DrawTexture(new Rect(12, 12, 230, 56), panel);
            GUI.Label(new Rect(22, 16, 220, 24), "Night " + Night.number + " · " + Night.name, mid);
            GUI.Label(new Rect(22, 40, 220, 24), Clock() + "  ·  dawn at 06:00", small);

            // top-centre: nest progress
            float bw = 300f, bx = (W - bw) / 2f;
            GUI.DrawTexture(new Rect(bx - 10, 12, bw + 20, 50), panel);
            GUI.Label(new Rect(bx, 14, bw, 22), "Nest  " + NestCount + " / " + Night.goal + "     Carrying  " + rat.carried.Count + " / " + rat.capacity, small);
            GUI.DrawTexture(new Rect(bx, 40, bw, 12), barBg);
            GUI.DrawTexture(new Rect(bx, 40, bw * Mathf.Clamp01(NestCount / (float)Night.goal), 12), barFill);

            // top-right: noise and stance
            if (rat.Noise > 0.05f || rat.Sneaking || rat.Hidden)
            {
                GUI.DrawTexture(new Rect(W - 182, 12, 170, 50), panel);
                GUI.Label(new Rect(W - 172, 14, 160, 22), rat.Hidden ? "Hidden" : rat.Sneaking ? "Sneaking" : "Noise", small);
                GUI.DrawTexture(new Rect(W - 172, 40, 150, 10), barBg);
                GUI.DrawTexture(new Rect(W - 172, 40, 150 * rat.Noise, 10), noiseFill);
            }

            DrawTasks(H);

            // toasts
            for (int i = 0; i < toasts.Count; i++)
                GUI.Label(new Rect(W / 2 - 300, 80 + i * 28, 600, 26), toasts[i].text, center);

            if (rat.HasJumpTarget && state == State.Play) GUI.Label(new Rect(W / 2 - 150, H - 60, 300, 24), "Space — jump", center);

            if (state == State.Pause)
            {
                GUI.DrawTexture(new Rect(0, 0, W, H), panel);
                GUI.Label(new Rect(0, H * 0.4f, W, 50), "Paused", big);
                GUI.Label(new Rect(0, H * 0.4f + 60, W, 30), "Click or Esc to continue · R to restart the night", center);
            }
            else if (state == State.Won || state == State.Lost)
            {
                GUI.DrawTexture(new Rect(0, 0, W, H), panel);
                GUI.Label(new Rect(0, H * 0.3f, W, 50), state == State.Won ? "The nest is full!" : "Dawn came", big);
                string sub = state == State.Won ? "The pups are fed. Next night: " + Night.teaser : "The nest has " + NestCount + " of " + Night.goal + ". Try again tonight.";
                GUI.Label(new Rect(W / 2 - 320, H * 0.3f + 60, 640, 50), sub, center);
                int side = Tasks.sideDone.Count, secrets = Tasks.secretDone.Count;
                GUI.Label(new Rect(0, H * 0.3f + 120, W, 30), "Side tasks " + side + " / " + Night.side.Length + "  ·  Secrets " + secrets + " / " + Night.secret.Length, center);
                GUI.Label(new Rect(0, H * 0.7f, W, 40), "Click or press R to play again", center);
            }
        }

        void DrawTasks(float H)
        {
            const float w = 360f;
            var lines = new List<(string text, GUIStyle style, float h)>();
            lines.Add((Night.goalText + "  " + NestCount + "/" + Night.goal, mid, 26));
            var cur = Tasks.Current;
            if (cur != null)
            {
                lines.Add(("▸ " + cur.text, small, 22));
                if (!string.IsNullOrEmpty(cur.hint)) lines.Add((cur.hint, hint, 38));
            }
            else lines.Add(("All tasks done! Fill the nest.", small, 22));
            for (int i = 0; i < Night.side.Length; i++)
            {
                if (!Tasks.SideVisible(i)) continue;
                string mark = Tasks.sideDone.Contains(i) ? "✓ " : Tasks.sideFailed.Contains(i) ? "✗ " : "○ ";
                lines.Add((mark + Night.side[i].text, small, 22));
            }
            for (int i = 0; i < Night.secret.Length; i++)
                if (Tasks.secretDone.Contains(i)) lines.Add(("★ " + Night.secret[i].text, small, 22));
            float total = 16f;
            foreach (var l in lines) total += l.h;
            float y = H - 12 - total;
            GUI.DrawTexture(new Rect(12, y, w, total), panel);
            y += 8;
            foreach (var l in lines)
            {
                GUI.Label(new Rect(22, y, w - 20, l.h), l.text, l.style);
                y += l.h;
            }
        }
    }
}
