using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace KitchenRat
{
    /// <summary>Things that happened this night that "keep" tasks and the results screen ask about.</summary>
    public class RunFlags { public bool catWoke, chased, seenOwner, poisonDelivered, caught; }

    /// <summary>
    /// One night, ported from the prototype's update(): food, delivery, noise, the wanted level and its threats,
    /// lives, sniffing, mousetraps, poison, tasks, the clock and the HUD (IMGUI for now).
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }
        static readonly int[] StarAt = { 10, 24, 40, 58, 80 };

        [Header("Scene (set by the builder)")]
        public string nightId = "kitchen";
        public RatController rat;
        public FollowCamera followCam;
        public CatAI cat;
        public OwnerAI owner;
        public Transform holePoint;
        public string[] foodTypes = new string[0];
        public GameObject[] foodModels = new GameObject[0];
        public GameObject trapModel;
        public float unitScale = 1f;

        public Night Night { get; private set; }
        public TaskTracker Tasks { get; private set; }
        public NavGrid Grid { get; private set; }
        public RunFlags run = new RunFlags();
        public int Fed { get; private set; }
        public int Lives { get; private set; } = 3;
        public int Stars { get; private set; }
        public float NightTime { get; private set; }
        public float GraceT { get; private set; }
        public bool Playing => state == State.Play;
        [System.NonSerialized] public int InHum;
        public Vector3 HolePoint => holePoint ? holePoint.position : Vector3.zero;

        enum State { Intro, Play, Pause, Won, Lost }
        State state = State.Intro;
        string endTitle = "", endText = "";
        float evidence, alarm, unseenT, refillT, noiseT, bumpT;
        int maxStars;
        readonly HashSet<int> starsDone = new HashSet<int>();
        readonly List<Food> foods = new List<Food>();
        readonly List<Trap> traps = new List<Trap>();
        readonly List<Surface> highSurfaces = new List<Surface>();
        Zone[] zones;
        Knockable[] knockables;
        bool sniffing;
        float sniffHold;
        readonly List<Food> sniffTargets = new List<Food>();
        readonly List<LineRenderer> trails = new List<LineRenderer>();

        void Awake()
        {
            I = this;
            Night = Nights.Load(nightId);
            Tasks = new TaskTracker(Night.tasks);
            Tasks.Completed += t => Toast("✓ " + t);
            Tasks.Failed += t => Toast("✗ " + t);
            Tasks.onSurface = arg => !rat.Jumping && rat.SurfaceId.StartsWith(arg);
            Tasks.hiddenIn = arg => rat.HideKind == arg;
            Tasks.keepBroken = KeepBroken;
        }

        void Start()
        {
            zones = FindObjectsByType<Zone>(FindObjectsSortMode.None);
            knockables = FindObjectsByType<Knockable>(FindObjectsSortMode.None);
            foods.AddRange(FindObjectsByType<Food>(FindObjectsSortMode.None));
            traps.AddRange(FindObjectsByType<Trap>(FindObjectsSortMode.None));
            foreach (var s in FindObjectsByType<Surface>(FindObjectsSortMode.None))
                if (s.id != "fridge" && s.id != "floor") highSurfaces.Add(s);
            Physics.SyncTransforms();
            var noGo = new List<Zone>();
            foreach (var z in zones) if (z is HideSpot h && h.id != "crack") noGo.Add(z);
            Grid = new NavGrid(noGo);

            if (cat) cat.Setup(Night);
            if (owner) owner.Setup(Night, Night.door > 0 ? Nights.World(935, Night.door) : Nights.World(935, 300));
            for (int i = 0; i < Night.food.randomCrumb; i++) SpawnRandom("crumb");
            for (int i = 0; i < Night.food.randomCheese; i++) SpawnRandom("cheese");
            if (Night.poisonStart > 0)
            {
                var c = foods.FindAll(f => f.IsCheese && string.IsNullOrEmpty(f.id) && !f.poison);
                for (int k = 0; k < Night.poisonStart && c.Count > 0; k++) { int j = Random.Range(0, c.Count); c[j].MakePoison(); c.RemoveAt(j); }
            }
            rat.Landed += OnLanded;
            rat.Frozen = true;
            for (int i = 0; i < 3; i++) trails.Add(MakeTrail());
        }

        bool KeepBroken(string a)
        {
            switch (a)
            {
                case "catWoke": return run.catWoke;
                case "chased": return run.chased;
                case "caught": return Lives < 3;
                case "seenOwner": return run.seenOwner;
                case "poison": return run.poisonDelivered;
                default: return Tasks.knocked.Contains(a);
            }
        }

        // ---------- events ----------

        /// <summary>A noise heard within radius (m). amt: how much it disturbs a sleeping cat at point-blank range (1 wakes it).</summary>
        public void Noise(Vector3 at, float radius, string label, bool big, float amt = -1f, bool fromKnock = false)
        {
            if (amt < 0f) amt = big ? 0.9f : radius > 1.5f ? 0.3f : 0.4f;
            alarm += big ? 7f : radius > 1.5f ? 0.5f : radius > 1f ? 2f : 0f;
            if (!string.IsNullOrEmpty(label)) Bubble(label, at + Vector3.up * 0.24f, 1.4f, new Color(0.95f, 0.76f, 0.3f));
            if (owner) owner.Hear(at, radius, big);
            if (cat) cat.Hear(at, radius, big, amt, fromKnock);
        }

        public void AddAlarm(float a) { alarm += a; }

        public void Deliver()
        {
            int poison = 0, value = 0;
            bool cheese = false;
            foreach (var f in rat.carried)
            {
                if (f.poison) poison++;
                value += f.Value;
                if (f.IsCheese && !f.poison) cheese = true;
                if (!string.IsNullOrEmpty(f.id)) Tasks.delivered.Add(f.id);
                foods.Remove(f);
                Destroy(f.gameObject);
            }
            Tasks.deliveredAny = true;
            if (rat.CarryWeight >= 3) Tasks.SetFlag("full");
            rat.carried.Clear();
            Fed = Mathf.Max(0, Fed + value - poison * 4);
            if (poison > 0)
            {
                run.poisonDelivered = true;
                Bubble("Poison! −" + poison * 4, HolePoint + Vector3.up * 0.32f, 1.6f, new Color(0.6f, 0.88f, 0.4f));
                Bubble("Ew! Tummy ache…", HolePoint + Vector3.up * 0.22f, 2f);
            }
            else
            {
                Bubble("+" + value, HolePoint + Vector3.up * 0.32f, 1.4f, new Color(0.95f, 0.76f, 0.3f));
                int left = Night.goal - Fed;
                Bubble(cheese ? "Cheese! Yay!" : left > 8 ? "Squeak! More!" : left > 3 ? "Almost full!" : "Just a little more!", HolePoint + Vector3.up * 0.22f, 1.8f);
            }
            while (Night.food.refill > 0 && LooseFood() < Night.food.refill + 3) if (!SpawnRandom(null)) break;
        }

        public void Caught(string text, Vector3 at)
        {
            if (GraceT > 0f || state != State.Play) return;
            Lives--;
            run.caught = true;
            Bubble(text, at, 1.6f, new Color(0.91f, 0.4f, 0.29f));
            foreach (var f in rat.carried)
            {
                f.carried = false;
                f.transform.SetParent(null, true);
                Vector3 p = rat.transform.position + new Vector3(Random.Range(-0.15f, 0.15f), 0.3f, Random.Range(-0.15f, 0.15f));
                if (Physics.Raycast(p, Vector3.down, out var hit, 3f, RatController.Mask, QueryTriggerInteraction.Ignore)) p = hit.point;
                f.transform.SetPositionAndRotation(p, Quaternion.identity);
            }
            rat.carried.Clear();
            Respawn();
            GraceT = 3f;
            if (cat) cat.AfterCatch();
            alarm += 10f;
            if (Lives <= 0) EndNight(false, "You got caught", "The pups got " + Fed + " of " + Night.goal + " and are waiting for Mom. Top wanted level: " + StarText(maxStars) + ".");
        }

        void Respawn()
        {
            Vector3 p = HolePoint + new Vector3(0.22f, 0.02f, 0.22f);
            rat.Teleport(p, Quaternion.Euler(0f, 45f, 0f));
            if (followCam) followCam.Snap(45f);
        }

        public void KnockLanded(Knockable k, Vector3 at)
        {
            Noise(at, 4.6f, k.Sound, true, -1f, true);
            if (!string.IsNullOrEmpty(k.spawn)) Spawn(k.spawn, at + new Vector3(0.14f, 0f, 0f), "", false);
            foreach (var t in traps)
            {
                if (t.sprung || Flat(t.transform.position - at).magnitude > 0.24f) continue;
                t.Spring();
                Spawn("cheese", t.transform.position + new Vector3(0.1f, 0f, -0.08f), "bait", false);
                Tasks.Flag("disarm");
                Bubble("Snap! Disarmed", t.transform.position + Vector3.up * 0.3f, 1.4f, new Color(0.62f, 0.82f, 0.48f));
            }
        }

        void OnLanded(float drop)
        {
            if (drop > 0.5f && rat.SurfaceId == "floor") Noise(rat.transform.position, 1.6f, "Thud", false, 0.55f);
            foreach (var z in zones) if (z is NoisyZone nz && z.Contains(rat.transform.position)) nz.OnLanded(rat);
        }

        // ---------- loop ----------

        void Update()
        {
            float dt = Time.deltaTime;
            TickMessages(Time.unscaledDeltaTime);
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

            NightTime += dt;
            if (NightTime >= Night.seconds) { EndNight(false, "Dawn", "The owners are waking up. The pups got " + Fed + " of " + Night.goal + ". There is always tomorrow night."); return; }
            GraceT = Mathf.Max(0f, GraceT - dt);

            Vector3 rp = rat.transform.position;
            TickRatNoise(dt);
            PickUp(rp);
            TickZones(rp, dt);
            TickKnockables(rp);
            TickSniff(dt);
            TickFoodVisibility(rp);
            foreach (var t in traps)
            {
                if (t.sprung || rp.y > 0.05f || rat.Jumping || Flat(t.transform.position - rp).magnitude > 0.12f) continue;
                t.Spring();
                Caught("SNAP!", t.transform.position + Vector3.up * 0.26f);
                break;
            }
            if (state != State.Play) return;
            refillT -= dt;
            if (refillT <= 0f) { refillT = 3f; if (Night.food.refill > 0 && LooseFood() < Night.food.refill) SpawnRandom(null); }
            TickFlags();
            Tasks.Tick();
            TickWanted(dt);
            bool done = Fed >= Night.goal && (!Tasks.HasTasks || Tasks.ChainDone);
            if (done) EndNight(true, "The nest is full!", "The pups are fed. Next night: " + Night.teaser);
        }

        void TickRatNoise(float dt)
        {
            noiseT -= dt;
            bumpT -= dt;
            if (!rat.Moving || rat.Jumping) return;
            bool floor = rat.SurfaceId == "floor";
            if (rat.Dragging && noiseT <= 0f) { noiseT = 0.6f; Noise(rat.transform.position, rat.Sneaking ? 0.6f : 1.2f, null, false, rat.Sneaking ? 0.05f : 0.15f); }
            else if (rat.Running && noiseT <= 0f) { noiseT = 0.35f; Noise(rat.transform.position, 2.1f, null, false, 0.3f); }
            else if (!rat.Running && !rat.Sneaking && floor && InHum == 0 && noiseT <= 0f) { noiseT = 0.45f; Noise(rat.transform.position, 0.95f, null, false, 0.1f); }
            if (rat.Running && floor && rat.Blocked && bumpT <= 0f) { bumpT = 0.9f; Noise(rat.transform.position, 1.7f, "Thump!", false, 0.45f); }
        }

        void PickUp(Vector3 rp)
        {
            if (rat.Jumping) return;
            for (int i = foods.Count - 1; i >= 0; i--)
            {
                var f = foods[i];
                if (f.carried || f.hidden) continue;
                Vector3 d = f.transform.position - rp;
                if (Mathf.Abs(d.y) > 0.12f || Flat(d).magnitude > 0.17f) continue;
                if (f.isFind)
                {
                    Toast(string.IsNullOrEmpty(f.label) ? "A find for the nest!" : f.label);
                    Tasks.SetFlag(f.type);
                    Tasks.Flag("collected");
                    foods.RemoveAt(i);
                    Destroy(f.gameObject);
                    continue;
                }
                if (rat.CarryWeight + f.Weight > rat.capacity) continue;
                rat.Carry(f);
                if (!string.IsNullOrEmpty(f.id))
                {
                    Tasks.picked.Add(f.id);
                    if (owner && owner.mode == OwnerAI.Mode.Drink) Tasks.SetFlag("underNose");
                }
                if (!f.poison) evidence += f.IsCheese ? 9f : 3f;
                if (f.IsCheese) Bubble("Cheeese!", rp + Vector3.up * 0.3f, 1.2f);
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
                if (k.knocked || rat.Jumping) continue;
                Vector3 d = k.transform.position - rp;
                if (Mathf.Abs(d.y) > 0.2f) continue;
                float dist = Flat(d).magnitude;
                if (k.trap && dist < 0.22f && rat.Moving && !rat.Sneaking)
                {
                    k.Knock(k.pushDir);
                    Bubble("Oops!", rp + Vector3.up * 0.3f, 1.2f);
                }
                else if (!k.trap && push && dist < 0.3f)
                {
                    k.Knock(Flat(d).sqrMagnitude > 1e-4f ? Flat(d) : rat.transform.forward);
                    Bubble("Hee hee", rp + Vector3.up * 0.3f, 1f);
                    push = false;
                }
            }
        }

        void TickSniff(float dt)
        {
            bool want = GameInput.Sniff && !rat.Jumping;
            Vector3 rp = rat.transform.position;
            if (want && !sniffing)
            {
                sniffing = true;
                sniffHold = 0f;
                foreach (var t in traps)
                {
                    if (t.sprung || Vector3.Distance(t.transform.position, rp) > 2.6f) continue;
                    Bubble("Trap!", t.transform.position + Vector3.up * 0.26f, 1.4f, new Color(0.91f, 0.4f, 0.29f));
                    if (!t.found) Tasks.Flag("trapFound");
                    t.Reveal();
                }
            }
            if (!want) sniffing = false;
            if (!sniffing) { foreach (var tr in trails) tr.enabled = false; return; }
            float before = sniffHold;
            sniffHold += dt;
            if (sniffHold > 0.6f) Tasks.SetFlag("sniffed");
            if (before <= 0.35f && sniffHold > 0.35f || Mathf.Floor(before / 0.5f) != Mathf.Floor(sniffHold / 0.5f)) PickScentTargets(before <= 0.35f);
            for (int i = 0; i < trails.Count; i++)
            {
                var tr = trails[i];
                tr.enabled = i < sniffTargets.Count && sniffTargets[i] && sniffHold > 0.35f;
                if (!tr.enabled) continue;
                DrawTrail(tr, rat.mouth ? rat.mouth.position : rp, sniffTargets[i].transform.position, sniffTargets[i].poison, i);
            }
        }

        void PickScentTargets(bool first)
        {
            Vector3 rp = rat.transform.position;
            var cand = new List<(Food f, float d)>();
            foreach (var f in foods)
            {
                if (f.carried || f.isFind) continue;
                Vector3 d = f.transform.position - rp;
                float score = Flat(d).magnitude + Mathf.Abs(d.y) * 0.6f - (f.IsCheese ? 1.2f : 0f);
                if (score < 9f) cand.Add((f, score));
            }
            cand.Sort((a, b) => a.d.CompareTo(b.d));
            sniffTargets.Clear();
            for (int i = 0; i < cand.Count && i < 3; i++)
            {
                var f = cand[i].f;
                sniffTargets.Add(f);
                f.revealT = 7f;
                if (f.hidden && Vector3.Distance(f.transform.position, rp) < 1.6f) { f.hidden = false; Bubble("Something hidden here!", f.transform.position + Vector3.up * 0.2f, 1.6f); }
            }
            if (!first) return;
            if (sniffTargets.Count == 0) { Bubble("I can’t smell anything…", rp + Vector3.up * 0.34f, 1.5f); return; }
            var t = sniffTargets[0];
            Vector3 to = t.transform.position - rp;
            Vector3 camF = followCam ? Flat(followCam.transform.forward) : rat.transform.forward;
            float rel = Vector3.SignedAngle(camF, Flat(to), Vector3.up), ar = Mathf.Abs(rel);
            string dir = ar < 29f ? "ahead" : ar > 149f ? "behind" : rel > 0f ? "to the right" : "to the left";
            string up = to.y > 0.2f ? ", up high" : to.y < -0.2f ? ", down low" : "";
            string what = t.poison ? "Ew, poisoned cheese" : t.IsCheese ? "Cheese" : "Crumbs";
            Bubble(what + " " + dir + up + " · " + (Mathf.Round(Flat(to).magnitude * 10f) / 10f) + " m", rp + Vector3.up * 0.34f, 2.2f);
        }

        void TickFoodVisibility(Vector3 rp)
        {
            foreach (var f in foods)
            {
                if (f.carried) continue;
                bool v = !f.hidden && (Night.openFood || f.isFind || f.revealT > 0f || Vector3.Distance(f.transform.position, rp) < 1.6f);
                f.SetVisible(v);
            }
        }

        void TickFlags()
        {
            Vector3 rp = rat.transform.position;
            if (cat && cat.gameObject.activeSelf)
            {
                float dc = Flat(cat.transform.position - rp).magnitude;
                if (cat.mode == CatAI.Mode.Sleep && dc < 0.95f) Tasks.SetFlag("passCat");
                if (rat.Hidden && cat.Awake && dc < 1.4f) Tasks.SetFlag("hidNearCat");
                if (Night.cat == "eating" && cat.mode == CatAI.Mode.Sleep) Tasks.SetFlag("catNapping");
            }
            if (owner && owner.InRoom)
            {
                if (rat.Hidden) Tasks.SetFlag("hidFromOwner");
                if (owner.mode == OwnerAI.Mode.Drink) Tasks.SetFlag("ownerDrinking");
            }
        }

        void TickWanted(float dt)
        {
            bool seen = (cat && cat.Sees) || (owner && owner.Sees);
            unseenT = seen ? 0f : unseenT + dt;
            if (rat.InNest && unseenT > 1f) alarm -= dt * 14f;
            else if (unseenT > 4f) alarm -= dt * 5f;
            alarm = Mathf.Clamp(alarm, 0f, 60f);
            int ns = 0;
            if (Night.wanted) foreach (int t in StarAt) if (evidence + alarm >= t) ns++;
            if (ns > Stars) OnStars(ns, Stars);
            Stars = ns;
            maxStars = Mathf.Max(maxStars, Stars);
        }

        void OnStars(int ns, int os)
        {
            for (int s = os + 1; s <= ns; s++)
            {
                if (!starsDone.Add(s)) continue;
                string stars = new string('★', s);
                string t = s - 1 < Night.threats.Length ? Night.threats[s - 1] : null;
                if (t != null)
                {
                    TriggerThreat(t);
                    switch (t)
                    {
                        case "cat": Banner(stars + " The cat woke up", "It can’t climb after you, but it will wait below. Hide to lose it.", 5f); break;
                        case "owner": Banner(stars + " The owner woke up", "He can spot you even on tables. Hide under furniture or in a crack.", 5f); break;
                        case "traps": Banner(stars + " Mousetraps!", "The owner set traps. They smell like cheese too, so sniff first (hold E).", 5f); break;
                        case "poison": Banner(stars + " Poisoned cheese", "Poisoned cheese smells green. Sniff before you grab.", 5f); break;
                        default: Banner(stars + " " + t, "", 4f); break;
                    }
                }
                else if (Night.threats.Length == 0) Banner(stars + " The house is restless", string.IsNullOrEmpty(Night.starTip) ? "Everyone is faster and sharper now" : Night.starTip, 3.5f);
                else
                {
                    Banner(stars + " High alert", "Everyone in the house is faster and sharper now", 4.5f);
                    if (System.Array.IndexOf(Night.threats, "traps") >= 0 && s == 5) PlaceTraps(2);
                }
            }
        }

        void TriggerThreat(string t)
        {
            if (t == "cat" && cat) cat.WakeUp();
            if (t == "traps") PlaceTraps(3);
            if (t == "poison")
            {
                var c = foods.FindAll(f => f.IsCheese && !f.poison && !f.carried);
                if (c.Count > 0) c[Random.Range(0, c.Count)].MakePoison();
                SpawnRandom("cheese");
            }
        }

        // ---------- spawning ----------

        int LooseFood() { int n = 0; foreach (var f in foods) if (!f.carried && !f.isFind) n++; return n; }

        GameObject ModelFor(string type)
        {
            for (int i = 0; i < foodTypes.Length && i < foodModels.Length; i++) if (foodTypes[i] == type) return foodModels[i];
            for (int i = 0; i < foodTypes.Length && i < foodModels.Length; i++) if (foodTypes[i] == "cheese") return foodModels[i];
            return null;
        }

        public Food Spawn(string type, Vector3 at, string tag, bool poison)
        {
            var model = ModelFor(type);
            if (!model) return null;
            var go = Instantiate(model, at, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
            go.transform.localScale *= unitScale;
            var f = go.AddComponent<Food>();
            f.type = type;
            f.id = tag ?? "";
            if (poison) f.MakePoison();
            foods.Add(f);
            return f;
        }

        bool SpawnRandom(string type)
        {
            if (type == null) type = Random.value < 0.3f ? "cheese" : "crumb";
            bool cheese = type == "cheese";
            bool high = highSurfaces.Count > 0 && Random.value < (cheese ? (Night.openFood ? 0.45f : 0.8f) : 0.25f);
            bool poison = cheese && Stars >= Night.ThreatStar("poison") && Random.value < 0.45f;
            for (int tries = 0; tries < 60; tries++)
            {
                Vector3 p;
                if (high)
                {
                    var s = highSurfaces[Random.Range(0, highSurfaces.Count)];
                    var rs = s.GetComponentsInChildren<Renderer>();
                    if (rs.Length == 0) continue;
                    var b = rs[0].bounds;
                    foreach (var r in rs) b.Encapsulate(r.bounds);
                    Vector3 o = new Vector3(Random.Range(b.min.x + 0.12f, b.max.x - 0.12f), b.max.y + 0.3f, Random.Range(b.min.z + 0.12f, b.max.z - 0.12f));
                    if (!Physics.Raycast(o, Vector3.down, out var hit, 2f, RatController.Mask, QueryTriggerInteraction.Ignore)) continue;
                    if (hit.normal.y < 0.85f || hit.point.y > 1.2f || hit.collider.GetComponentInParent<Surface>() != s) continue;
                    p = hit.point;
                }
                else
                {
                    p = Grid.RandomFree(1.2f, HolePoint);
                    if (Physics.CheckSphere(p + Vector3.up * 0.08f, 0.05f, RatController.Mask, QueryTriggerInteraction.Ignore)) continue;
                }
                bool clash = false;
                foreach (var f in foods) if (!f.carried && Flat(f.transform.position - p).magnitude < 0.24f) { clash = true; break; }
                foreach (var k in knockables) if (Flat(k.transform.position - p).magnitude < 0.24f) clash = true;
                if (clash) continue;
                return Spawn(type, p, "", poison) != null;
            }
            return false;
        }

        public void PlaceTraps(int n)
        {
            if (!trapModel) return;
            int placed = 0;
            for (int t = 0; t < 500 && placed < n; t++)
            {
                Vector3 p = Grid.RandomFree(0f, Vector3.zero);
                if (Vector3.Distance(p, HolePoint) < 1.5f || Vector3.Distance(p, rat.transform.position) < 0.9f) continue;
                if (owner && Vector3.Distance(p, owner.door) < 0.7f) continue;
                bool near = false;
                foreach (var q in traps) if (Vector3.Distance(q.transform.position, p) < 1f) near = true;
                if (near) continue;
                bool byFurniture = Grid.BlockedAt(p + Vector3.right * 0.45f) || Grid.BlockedAt(p + Vector3.left * 0.45f) || Grid.BlockedAt(p + Vector3.forward * 0.45f) || Grid.BlockedAt(p + Vector3.back * 0.45f);
                if (!byFurniture && Random.value < 0.7f) continue;
                AddTrap(p + new Vector3(Random.Range(-0.04f, 0.04f), 0f, Random.Range(-0.04f, 0.04f)), false);
                placed++;
            }
        }

        public Trap AddTrap(Vector3 at, bool hidden)
        {
            var go = Instantiate(trapModel, at, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
            go.transform.localScale *= unitScale;
            var t = go.AddComponent<Trap>();
            t.hidden = hidden;
            traps.Add(t);
            return t;
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

        void EndNight(bool won, string title, string text)
        {
            if (won) Tasks.FinishNight();
            state = won ? State.Won : State.Lost;
            endTitle = title;
            endText = text;
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

        void OnApplicationFocus(bool focus) { if (!focus && state == State.Play) SetPaused(true); }

        static Vector3 Flat(Vector3 v) { v.y = 0f; return v; }
        static string StarText(int n) => n == 0 ? "none" : new string('★', n);

        // ---------- messages ----------

        class Msg { public string text; public Transform follow; public Vector3 pos; public float h, t, rise; public Color col; }
        readonly List<Msg> bubbles = new List<Msg>();
        readonly List<(string text, float t)> toasts = new List<(string, float)>();
        string bannerT = "", bannerS = "";
        float bannerTime;

        public void Bubble(string text, Vector3 at, float dur, Color? col = null) =>
            bubbles.Add(new Msg { text = text, pos = at, t = dur, col = col ?? Color.white });

        public void Bubble(string text, Transform follow, float height, float dur) =>
            bubbles.Add(new Msg { text = text, follow = follow, h = height, t = dur, col = Color.white });

        public void Toast(string text)
        {
            toasts.RemoveAll(t => t.text == text);
            toasts.Add((text, 3f));
            if (toasts.Count > 3) toasts.RemoveAt(0);
        }

        public void Banner(string title, string sub, float dur)
        {
            bannerT = title;
            bannerS = sub;
            bannerTime = dur;
        }

        void TickMessages(float dt)
        {
            for (int i = bubbles.Count - 1; i >= 0; i--) { bubbles[i].t -= dt; bubbles[i].rise += dt * 0.08f; if (bubbles[i].t <= 0f) bubbles.RemoveAt(i); }
            for (int i = toasts.Count - 1; i >= 0; i--) { var t = toasts[i]; t.t -= dt; if (t.t <= 0f) toasts.RemoveAt(i); else toasts[i] = t; }
            bannerTime -= dt;
        }

        // ---------- scent trails ----------

        LineRenderer MakeTrail()
        {
            var tr = new GameObject("Scent trail").AddComponent<LineRenderer>();
            tr.positionCount = 24;
            tr.widthMultiplier = 0.008f;
            tr.material = new Material(Shader.Find("Sprites/Default"));
            tr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            tr.enabled = false;
            return tr;
        }

        void DrawTrail(LineRenderer tr, Vector3 from, Vector3 to, bool poison, int i)
        {
            Vector3 a = from + Vector3.up * 0.05f, b = to + Vector3.up * 0.03f;
            Vector3 side = Vector3.Cross(b - a, Vector3.up).normalized;
            for (int k = 0; k < tr.positionCount; k++)
            {
                float t = k / (tr.positionCount - 1f);
                tr.SetPosition(k, Vector3.Lerp(a, b, t) + Vector3.up * Mathf.Sin(t * Mathf.PI) * 0.15f + side * Mathf.Sin(t * 12f + Time.time * 3f + i) * 0.02f);
            }
            float alpha = Mathf.Clamp01((sniffHold - 0.35f) * 2f) * (0.55f + 0.25f * Mathf.Sin(Time.time * 5f)) * (i == 0 ? 1f : 0.55f);
            var c = poison ? new Color(0.56f, 0.88f, 0.38f, alpha) : new Color(1f, 0.85f, 0.5f, alpha);
            tr.startColor = c;
            tr.endColor = new Color(c.r, c.g, c.b, alpha * 0.4f);
        }

        // ---------- HUD ----------

        GUIStyle big, mid, small, hint, center, bubble, bannerStyle;
        Texture2D panel, barBg, barFill, noiseFill, sleepFill;

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
            bannerStyle = new GUIStyle(mid) { alignment = TextAnchor.MiddleCenter, fontSize = 22 };
            bubble = new GUIStyle(GUI.skin.box) { fontSize = 14, alignment = TextAnchor.MiddleCenter, wordWrap = false };
            panel = Tex(new Color(0.05f, 0.06f, 0.1f, 0.72f));
            barBg = Tex(new Color(1f, 1f, 1f, 0.15f));
            barFill = Tex(new Color(1f, 0.72f, 0.35f, 0.95f));
            noiseFill = Tex(new Color(1f, 0.35f, 0.3f, 0.9f));
            sleepFill = Tex(new Color(0.55f, 0.65f, 1f, 0.9f));
        }

        string Clock()
        {
            float h = 23f + 7f * Mathf.Clamp01(NightTime / Night.seconds);
            int hh = (int)h % 24, mm = (int)((h - Mathf.Floor(h)) * 60f);
            return hh.ToString("00") + ":" + mm.ToString("00");
        }

        bool ToScreen(Vector3 world, float s, out Vector2 p)
        {
            p = Vector2.zero;
            var cam = Camera.main;
            if (!cam) return false;
            var sp = cam.WorldToScreenPoint(world);
            if (sp.z <= 0f) return false;
            p = new Vector2(sp.x / s, (Screen.height - sp.y) / s);
            return true;
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
                GUI.Label(new Rect(0, H * 0.26f, W, 50), "Night " + Night.number + " · " + Night.name, big);
                GUI.Label(new Rect(W / 2 - 320, H * 0.26f + 60, 640, 30), Night.startTitle, center);
                GUI.Label(new Rect(W / 2 - 320, H * 0.26f + 90, 640, 50), Night.startSub, center);
                if (!string.IsNullOrEmpty(Night.introMom)) GUI.Label(new Rect(W / 2 - 320, H * 0.26f + 150, 640, 60), "Mom: “" + Night.introMom + "”", hint);
                GUI.Label(new Rect(W / 2 - 380, H * 0.64f, 760, 60),
                    "WASD move · Mouse look · Shift run · Ctrl or C sneak · Space jump (aim at the yellow ring) · E or right mouse sniff · F push · Esc pause", center);
                GUI.Label(new Rect(0, H * 0.76f, W, 40), "Click to start", big);
                return;
            }

            // world-space bubbles
            foreach (var b in bubbles)
            {
                Vector3 wp = (b.follow ? b.follow.position + Vector3.up * b.h : b.pos) + Vector3.up * b.rise;
                if (!ToScreen(wp, s, out var p)) continue;
                var size = bubble.CalcSize(new GUIContent(b.text));
                var old = GUI.color;
                GUI.color = new Color(b.col.r, b.col.g, b.col.b, Mathf.Clamp01(b.t * 2f));
                GUI.Label(new Rect(p.x - size.x / 2 - 6, p.y - size.y, size.x + 12, size.y + 4), b.text, bubble);
                GUI.color = old;
            }
            // the sleeping cat's Zzz bar
            if (cat && cat.gameObject.activeSelf && cat.mode == CatAI.Mode.Sleep && Vector3.Distance(cat.transform.position, rat.transform.position) < 4f
                && ToScreen(cat.transform.position + Vector3.up * 0.5f, s, out var cp))
            {
                GUI.Label(new Rect(cp.x - 40, cp.y - 22, 80, 18), "Zzz", center);
                GUI.DrawTexture(new Rect(cp.x - 30, cp.y - 4, 60, 6), barBg);
                GUI.DrawTexture(new Rect(cp.x - 30, cp.y - 4, 60 * cat.SleepMeter, 6), sleepFill);
            }

            // top-left: night, clock, lives
            GUI.DrawTexture(new Rect(12, 12, 250, 78), panel);
            GUI.Label(new Rect(22, 16, 240, 24), "Night " + Night.number + " · " + Night.name, mid);
            GUI.Label(new Rect(22, 40, 240, 22), Clock() + "  ·  dawn at 06:00", small);
            GUI.Label(new Rect(22, 62, 240, 22), "Lives " + new string('♥', Mathf.Max(0, Lives)) + new string('♡', Mathf.Max(0, 3 - Lives)) + (Night.wanted ? "   Wanted " + (Stars > 0 ? new string('★', Stars) : "—") : ""), small);

            // top-centre: nest progress
            float bw = 300f, bx = (W - bw) / 2f;
            GUI.DrawTexture(new Rect(bx - 10, 12, bw + 20, 50), panel);
            GUI.Label(new Rect(bx, 14, bw, 22), "Nest  " + Fed + " / " + Night.goal + "     Carrying  " + rat.CarryWeight + " / " + rat.capacity, small);
            GUI.DrawTexture(new Rect(bx, 40, bw, 12), barBg);
            GUI.DrawTexture(new Rect(bx, 40, bw * Mathf.Clamp01(Fed / (float)Mathf.Max(1, Night.goal)), 12), barFill);

            // top-right: noise and stance
            if (rat.Noise > 0.05f || rat.Sneaking || rat.Hidden)
            {
                GUI.DrawTexture(new Rect(W - 182, 12, 170, 50), panel);
                GUI.Label(new Rect(W - 172, 14, 160, 22), rat.Hidden ? "Hidden" : rat.Sneaking ? "Sneaking" : "Noise", small);
                GUI.DrawTexture(new Rect(W - 172, 40, 150, 10), barBg);
                GUI.DrawTexture(new Rect(W - 172, 40, 150 * rat.Noise, 10), noiseFill);
            }

            if (bannerTime > 0f)
            {
                var old = GUI.color;
                GUI.color = new Color(1f, 1f, 1f, Mathf.Clamp01(bannerTime));
                GUI.DrawTexture(new Rect(W / 2 - 330, 84, 660, 74), panel);
                GUI.Label(new Rect(W / 2 - 320, 88, 640, 36), bannerT, bannerStyle);
                GUI.Label(new Rect(W / 2 - 320, 122, 640, 32), bannerS, center);
                GUI.color = old;
            }
            for (int i = 0; i < toasts.Count; i++) GUI.Label(new Rect(W / 2 - 300, 170 + i * 26, 600, 24), toasts[i].text, center);

            DrawTasks(H);
            if (rat.HasJumpTarget && state == State.Play) GUI.Label(new Rect(W / 2 - 150, H - 60, 300, 24), "Space — jump", center);

            if (state == State.Pause)
            {
                GUI.DrawTexture(new Rect(0, 0, W, H), panel);
                GUI.Label(new Rect(0, H * 0.4f, W, 50), "Paused", big);
                GUI.Label(new Rect(0, H * 0.4f + 60, W, 30), "Night " + Night.number + " · " + Night.name + ". The pups are waiting. Click or Esc to continue · R to restart", center);
            }
            else if (state == State.Won || state == State.Lost)
            {
                GUI.DrawTexture(new Rect(0, 0, W, H), panel);
                GUI.Label(new Rect(0, H * 0.28f, W, 50), endTitle, big);
                GUI.Label(new Rect(W / 2 - 340, H * 0.28f + 60, 680, 60), endText, center);
                float y = H * 0.28f + 130;
                var set = Tasks.set;
                if (Tasks.HasTasks)
                {
                    GUI.Label(new Rect(0, y, W, 24), "Main tasks " + Mathf.Min(Tasks.step, set.chain.Length) + " / " + set.chain.Length, center); y += 26;
                    for (int i = 0; i < set.side.Length; i++, y += 24) GUI.Label(new Rect(0, y, W, 24), (Tasks.sideDone.Contains(i) && state == State.Won ? "✓ " : "○ ") + "Side: " + set.side[i].text, center);
                    for (int i = 0; i < set.secret.Length; i++, y += 24) GUI.Label(new Rect(0, y, W, 24), Tasks.secretDone.Contains(i) ? "★ Secret: " + set.secret[i].text : "Secret: ???", center);
                }
                GUI.Label(new Rect(0, H * 0.8f, W, 40), "Click or press R to play again", center);
            }
        }

        void DrawTasks(float H)
        {
            const float w = 370f;
            var set = Tasks.set;
            var lines = new List<(string text, GUIStyle style, float h)>();
            lines.Add((set.goal + "  " + Mathf.Min(Fed, Night.goal) + "/" + Night.goal, mid, 26));
            var cur = Tasks.Current;
            if (cur != null)
            {
                lines.Add(("Step " + (Tasks.step + 1) + " of " + set.chain.Length + ":  " + cur.text, small, 22));
                if (!string.IsNullOrEmpty(cur.hint)) lines.Add((cur.hint, hint, 38));
            }
            else if (Fed < Night.goal) lines.Add(("Every task is done. Bring " + (Night.goal - Fed) + " more food home.", small, 22));
            for (int i = 0; i < set.side.Length; i++)
            {
                if (!Tasks.SideVisible(i)) continue;
                string mark = Tasks.sideDone.Contains(i) ? "✓ " : Tasks.sideFailed.Contains(i) ? "✗ " : "○ ";
                lines.Add((mark + "Side: " + set.side[i].text, small, 22));
            }
            for (int i = 0; i < set.secret.Length; i++)
                if (Tasks.secretDone.Contains(i)) lines.Add(("★ Secret: " + set.secret[i].text, small, 22));
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
