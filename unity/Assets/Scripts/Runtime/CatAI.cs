using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// The cat, ported from the prototype's updateCat. Modes:
    /// away · sleep (a sleep meter that noise lowers; half awake it lifts its head and looks) · eat → to bed ·
    /// wander / idle · investigate (a noise) · search · chase · watch (the rat is up high: it waits below).
    /// It can't climb, can't get under furniture, and loses you in hiding spots.
    /// </summary>
    public class CatAI : Agent
    {
        public enum Mode { Away, Sleep, Eat, ToBed, Wander, Idle, Investigate, Search, Chase, Watch }

        public Mode mode = Mode.Away;
        [Range(0, 1)] public float alert;
        [Range(0, 1)] public float sleep = 1f;
        public Vector3 bed, bowl;
        public bool Sees { get; private set; }
        public float SleepMeter => sleep;
        public bool Awake => mode != Mode.Away && mode != Mode.Sleep;

        Vector3 last;
        float lostT, searchT, watchT, idleT, sit = 1f, repath, meowT, zzzT = 1f, calmT, eatT, peek;
        int stage;
        bool goingHome;
        float graceAway;

        Night N => G.Night;

        public void Setup(Night n)
        {
            bed = n.Pos(n.catBed);
            bowl = n.bowl.Length >= 2 ? n.Pos(n.bowl) : bed;
            transform.position = bed;
            transform.rotation = Quaternion.LookRotation(Nights.Dir(Mathf.PI * 0.8f));
            switch (n.cat)
            {
                case "away": mode = Mode.Away; break;
                case "eating":
                    mode = Mode.Eat; sleep = 0f; eatT = n.eatTime;
                    transform.position = bowl + new Vector3(0.26f, 0f, -0.04f);
                    break;
                case "awake":
                    mode = Mode.Idle; idleT = 2.5f; sleep = 0f;
                    if (n.catStart.Length >= 2) { transform.position = n.Pos(n.catStart); transform.rotation = Quaternion.LookRotation(Vector3.forward); }
                    break;
                default: mode = Mode.Sleep; sleep = 1f; break;
            }
            gameObject.SetActive(mode != Mode.Away);
        }

        float SightRange => (mode == Mode.Idle && sit > 0.5f ? 1.5f + G.Stars * 0.1f : 2.6f + G.Stars * 0.15f) * N.catSense;
        bool RatHidden => Rat.Hidden || Rat.InNest;

        // ---------- hearing ----------

        public void Hear(Vector3 at, float radius, bool big, float amt, bool fromKnock)
        {
            if (mode == Mode.Away) return;
            float d = Flat(at - transform.position).magnitude;
            if (mode == Mode.Sleep)
            {
                if (d >= radius) return;
                sleep -= amt * (1f - d / radius) * (1f + G.Stars * 0.25f) * N.sleepSense;
                calmT = 2.5f;
                last = at;
                if (sleep <= 0f) WakeUp(at);
                return;
            }
            if (d < radius * N.catSense && mode != Mode.Chase && mode != Mode.Watch)
            {
                if (fromKnock && mode != Mode.Investigate) G.Tasks.Flag("lure");
                mode = Mode.Investigate;
                last = at;
                alert = Mathf.Max(alert, radius < 1f ? 0.25f : 0.4f);
                PathTo(at);
                sit = 0f;
                if (big || meowT <= 0f) { meowT = 2f; G.Bubble(big ? "Meow?" : "?", transform, 0.5f, 1.2f); }
            }
        }

        public void WakeUp(Vector3? toward = null)
        {
            if (mode == Mode.Away) { gameObject.SetActive(true); transform.position = bed; }
            else if (mode != Mode.Sleep) return;
            mode = Mode.Search;
            searchT = 1.8f; sit = 0.6f; sleep = 0f;
            G.AddAlarm(4f);
            if (toward.HasValue) Turn(toward.Value - transform.position, 1f);
            G.Bubble("MRRAW?!", transform, 0.46f, 1.6f);
            if (N.cat == "sleep" && !G.run.catWoke) G.Banner("You woke the cat!", "Now it prowls the room. Stay out of its sight and hide under furniture.", 4.5f);
            G.run.catWoke = true;
        }

        /// <summary>After it catches the rat it wanders off for a while.</summary>
        public void AfterCatch()
        {
            if (mode == Mode.Sleep || mode == Mode.Away) return;
            mode = Mode.Wander;
            alert = 0f; sit = 0f;
            path = Grid.FindPath(transform.position, Grid.RandomFree(3.8f, G.HolePoint));
            G.Bubble("Hmph.", transform, 0.5f, 1.2f);
        }

        static Vector3 Flat(Vector3 v) { v.y = 0f; return v; }

        // ---------- update ----------

        void Update()
        {
            if (!G.Playing) return;
            float dt = Time.deltaTime, dist = DistRat;
            Speed = 0f;
            meowT -= dt;
            if (mode == Mode.Away) { Sees = false; return; }

            if (mode == Mode.Eat || mode == Mode.ToBed)
            {
                if (mode == Mode.Eat)
                {
                    Turn(bowl - transform.position, dt * 4f);
                    eatT -= dt; zzzT -= dt;
                    if (zzzT <= 0f) { zzzT = 2.6f; G.Bubble("Crunch crunch", transform, 0.4f, 1.2f); }
                    if (eatT <= 0f) { mode = Mode.ToBed; PathTo(bed); G.Bubble("*yawn*", transform, 0.44f, 1.4f); }
                    Play("eat");
                }
                else if (!Follow(0.7f, dt)) { mode = Mode.Sleep; sleep = 1f; stage = 0; sit = 1f; transform.position = bed; }
                else Play("walk");
                // while eating it only notices you right next to it or right in front of it
                bool near = !RatHidden && (dist < 0.4f || (dist < 1.1f && AngleToRat() < 28f)) && LineOfSight();
                Sees = near;
                if (near) { mode = Mode.Chase; alert = 1f; G.Bubble("MEOW!", transform, 0.5f, 1.2f); }
                return;
            }

            if (mode == Mode.Sleep)
            {
                Sees = false;
                calmT -= dt;
                if (calmT <= 0f) sleep = Mathf.Min(1f, sleep + dt * 0.045f);
                int st = sleep > 0.6f ? 0 : sleep > 0.3f ? 1 : 2;
                if (st > stage) G.Bubble(st == 1 ? "Mrr…" : "…?", transform, 0.44f, 1.4f);
                stage = st;
                peek = Mathf.Lerp(peek, st == 2 ? 1f : st == 1 ? 0.35f : 0f, Mathf.Min(1f, dt * 3f));
                Play(st == 0 ? "sleep" : st == 1 ? "stir" : "head_up", 0.4f);
                if (st == 2)
                {
                    Turn(last - transform.position, dt * 2f);
                    bool peekSees = !RatHidden && dist < 1.7f && AngleToRat() < 46f && LineOfSight();
                    if (peekSees) { WakeUp(Rat.transform.position); alert = 0.8f; return; }
                }
                if (dist < 0.32f || G.Stars >= N.ThreatStar("cat")) WakeUp(Rat.transform.position);
                return;
            }

            bool ratHigh = Rat.transform.position.y >= 0.3f;
            bool inCone = dist < SightRange && AngleToRat() < 35.5f;
            Sees = G.GraceT <= 0f && !RatHidden && (inCone || dist < 0.34f) && LineOfSight();
            if (Sees) { alert += dt * (1.3f + (1f - dist / 2.6f) * 3f); last = Rat.transform.position; G.AddAlarm(dt * 4f); }
            else if (mode != Mode.Chase && mode != Mode.Watch) alert -= dt * 0.45f;
            alert = Mathf.Clamp01(alert);

            if (alert >= 1f && mode != Mode.Chase && mode != Mode.Watch)
            {
                mode = ratHigh ? Mode.Watch : Mode.Chase;
                lostT = 0f; watchT = 4f; repath = 0f; sit = 0f;
                G.AddAlarm(6f);
                G.Bubble(ratHigh ? "Meow?!" : "MEOW!", transform, 0.52f, 1.2f);
            }
            else if (alert > 0.35f && Sees && (mode == Mode.Wander || mode == Mode.Idle)) { mode = Mode.Investigate; PathTo(Rat.transform.position); sit = 0f; }

            float mul = 1f + G.Stars * 0.05f;
            switch (mode)
            {
                case Mode.Chase:
                    if (ratHigh && Sees) { mode = Mode.Watch; watchT = 4f; repath = 0f; break; }
                    lostT = Sees ? 0f : lostT + dt;
                    repath -= dt;
                    if (repath <= 0f) { repath = 0.25f; PathTo(Sees ? Rat.transform.position : last); }
                    if (!Follow(1.72f * mul, dt) && Sees) Turn(ToRat, dt * 7f);
                    if (lostT > 1.4f) { mode = Mode.Search; searchT = 2.4f; alert = 0.6f; }
                    break;
                case Mode.Watch:
                    repath -= dt;
                    if (repath <= 0f) { repath = 0.5f; PathTo(Grid.FreePoint(Rat.transform.position)); }
                    if (!Follow(1.2f, dt))
                    {
                        Turn(ToRat, dt * 5f);
                        if (meowT <= 0f && Sees) { meowT = 2.2f; G.Bubble(Random.value < 0.5f ? "Meow…" : "Get down here!", transform, 0.52f, 1.4f); }
                    }
                    watchT -= Sees ? dt * 0.35f : dt;
                    if (!ratHigh && Sees) { mode = Mode.Chase; lostT = 0f; repath = 0f; }
                    else if (watchT <= 0f) { mode = Mode.Wander; alert = 0.2f; path.Clear(); G.Bubble("Hmph.", transform, 0.5f, 1.2f); }
                    break;
                case Mode.Investigate:
                    if (!Follow(1f * mul, dt)) { mode = Mode.Search; searchT = 1.8f; }
                    break;
                case Mode.Search:
                    searchT -= dt;
                    transform.Rotate(0f, dt * 126f, 0f);
                    sit = Mathf.Max(0f, sit - dt * 2f);
                    if (searchT <= 0f) { mode = Mode.Wander; alert = Mathf.Min(alert, 0.2f); path.Clear(); }
                    break;
                case Mode.Idle:
                    idleT -= dt;
                    sit = idleT > 1.2f ? Mathf.Min(1f, sit + dt * 2f) : Mathf.Max(0f, sit - dt * 2f);
                    transform.Rotate(0f, Mathf.Sin(Time.time * 0.9f) * dt * 34f, 0f);
                    if (idleT <= 0f) { mode = Mode.Wander; path.Clear(); sit = 0f; }
                    break;
                default:
                    if (path.Count == 0)
                    {
                        goingHome = Random.value < 0.22f;
                        Vector3 home = N.bowl.Length >= 2 ? bowl + new Vector3(0.24f, 0f, 0f) : bed + new Vector3(0.36f, 0f, 0f);
                        PathTo(goingHome ? home : Grid.RandomFree(2.6f, transform.position));
                    }
                    if (!Follow(0.7f * (1f + G.Stars * 0.08f), dt)) { mode = Mode.Idle; idleT = goingHome ? 4f : 1.5f + Random.value * 3.5f; }
                    break;
            }
            if (mode == Mode.Chase) G.run.chased = true;

            if (Speed > 1.3f) Play("run", 0.15f);
            else if (Speed > 0.05f) Play("walk");
            else if (mode == Mode.Search) Play("look_around");
            else Play("idle_sit", 0.3f);

            if (G.GraceT <= 0f && !RatHidden && !Rat.Jumping && Rat.transform.position.y < 0.3f && dist < 0.3f)
            {
                Play("pounce", 0.05f);
                G.Caught("Gotcha!", transform.position + Vector3.up * 0.58f);
            }
        }
    }
}
