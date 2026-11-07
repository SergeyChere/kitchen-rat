using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// The owner, ported from the prototype's startVisit / updateHuman. He comes in through the door on the east wall,
    /// either on a schedule (a glass of water, a flashlight patrol) or when the wanted level reaches his star.
    /// He sees far (even onto tables), chases, swats with a slipper, and leaves when he loses interest.
    /// </summary>
    public class OwnerAI : Agent
    {
        public enum Mode { Away, Coming, Patrol, Look, Drink, Chase, Leaving }

        public Mode mode = Mode.Away;
        public Vector3 door;
        public Light flashlight;
        public Light roomLight;
        public bool Sees { get; private set; }
        public bool InRoom => mode != Mode.Away && mode != Mode.Coming;

        OwnerPlan plan;
        bool planActive, planStarted, chasedThisVisit, known;
        int visit, wp;
        float t, t2, seeT, lostT, lowT, sweep, repath;
        Vector3 last;
        GameObject body;

        Night N => G.Night;
        int OwnerStar => N.ThreatStar("owner");

        public void Setup(Night n, Vector3 doorPoint)
        {
            door = doorPoint;
            plan = n.HasOwnerPlan ? n.owner : null;
            eyeHeight = 1.5f;
            body = anim ? anim.gameObject : null;
            transform.position = door;
            Show(false);
        }

        void Show(bool on)
        {
            if (body) body.SetActive(on);
            if (flashlight) flashlight.enabled = on && plan != null && planActive && !plan.light;
        }

        void SetRoomLight(bool on) { if (roomLight) roomLight.enabled = on; }

        public void Hear(Vector3 at, float radius, bool big)
        {
            if ((mode == Mode.Patrol || mode == Mode.Look) && Vector3.Distance(transform.position, at) < (big ? 7f : 3.2f))
            {
                mode = Mode.Patrol;
                PathTo(at);
                last = at;
                known = true;
            }
        }

        void StartVisit()
        {
            visit++;
            planActive = true; planStarted = false; chasedThisVisit = false;
            mode = Mode.Coming; t = 2.4f;
            G.Bubble(plan.type == "water" ? "Stomp… stomp… *yawn*" : "Click. A flashlight…", door + Vector3.up * 1.2f, 2.2f);
            G.Banner(plan.type == "water" ? "The owner is coming!" : "Flashlight patrol!", "Hide under furniture or in a crack until he leaves.", 3.5f);
        }

        void EndVisit()
        {
            mode = Mode.Leaving;
            PathTo(door);
        }

        void Update()
        {
            if (!G.Playing) return;
            float dt = Time.deltaTime;
            Sees = false;
            Speed = 0f;
            if (OwnerStar > 5 && plan == null) return;

            if (plan != null && mode == Mode.Away && visit < plan.at.Length && G.NightTime >= plan.at[visit]) StartVisit();
            if (mode == Mode.Away)
            {
                if (G.Stars >= OwnerStar) { mode = Mode.Coming; t = 2.4f; G.Bubble("Stomp… stomp… stomp…", door + Vector3.up * 1.2f, 2.2f); }
                return;
            }
            if (mode == Mode.Coming)
            {
                t -= dt;
                if (t > 0f) return;
                mode = Mode.Patrol;
                transform.position = door;
                transform.rotation = Quaternion.LookRotation(Vector3.left);
                path.Clear(); lostT = 0f; seeT = 0f; lowT = 0f; t = 0f;
                Show(true);
                SetRoomLight(!(planActive && plan != null && !plan.light));
                G.Bubble(G.Stars >= 5 ? "That’s it, rat, you’re done!" : "Who’s rustling in here?!", transform, 1.95f, 2.4f);
                return;
            }
            if (mode == Mode.Patrol && planActive && !planStarted) { planStarted = true; path.Clear(); wp = 0; }

            t += dt;
            float dist = DistRat;
            bool inCone = dist < 3.3f && AngleToRat(sweep * Mathf.Rad2Deg) < 28.6f;
            Sees = mode != Mode.Leaving && !(Rat.Hidden || Rat.InNest) && (inCone || dist < 0.5f) && LineOfSight();
            if (Sees) { G.run.seenOwner = true; seeT += dt; last = Rat.transform.position; known = true; G.AddAlarm(dt * 12f); }
            else seeT = Mathf.Max(0f, seeT - dt * 0.5f);
            float mul = 1f + Mathf.Max(0, G.Stars - OwnerStar) * 0.05f;

            if (mode != Mode.Leaving && mode != Mode.Chase && seeT > 0.35f)
            {
                mode = Mode.Chase; lostT = 0f; repath = 0f;
                G.AddAlarm(6f);
                G.Bubble(Random.value < 0.5f ? "Why, you little…!" : "There you are!", transform, 1.95f, 1.6f);
            }

            switch (mode)
            {
                case Mode.Patrol:
                    sweep = Mathf.Sin(t * 1.3f) * 0.55f;
                    if (planActive && path.Count == 0)
                    {
                        if (plan.type == "water")
                        {
                            if (wp == 0) { PathTo(N.Pos(plan.stand)); wp = 1; }
                            else
                            {
                                mode = Mode.Drink; t2 = plan.stay > 0 ? plan.stay : 14f;
                                transform.rotation = Quaternion.LookRotation(Nights.Dir(plan.face));
                                G.Bubble("*glug glug*", transform, 1.95f, 2f);
                            }
                        }
                        else if (wp < plan.route.Length) { PathTo(Nights.World(plan.route[wp].x, plan.route[wp].y)); wp++; }
                        else EndVisit();
                        if (mode != Mode.Patrol) break;
                    }
                    if (path.Count == 0)
                    {
                        Vector3 target = known && Random.value < 0.55f
                            ? Grid.FreePoint(last + new Vector3(Random.Range(-1.1f, 1.1f), 0f, Random.Range(-1.1f, 1.1f)))
                            : Grid.RandomFree(2f, transform.position);
                        PathTo(target);
                    }
                    if (!Follow(0.85f * mul, dt)) { mode = Mode.Look; t2 = 1.6f; path.Clear(); }
                    break;
                case Mode.Look:
                    t2 -= dt;
                    sweep = Mathf.Sin(t * 2.4f) * 0.9f;
                    if (t2 <= 0f) { mode = Mode.Patrol; if (planActive && chasedThisVisit) EndVisit(); }
                    break;
                case Mode.Drink:
                    t2 -= dt;
                    sweep = Mathf.Sin(t * 0.7f) * 0.15f;
                    if (t2 <= 0f) { G.Bubble("Ahh. Back to bed.", transform, 1.95f, 1.8f); EndVisit(); }
                    break;
                case Mode.Chase:
                    chasedThisVisit = true;
                    sweep *= Mathf.Max(0f, 1f - dt * 5f);
                    lostT = Sees ? 0f : lostT + dt;
                    repath -= dt;
                    if (repath <= 0f) { repath = 0.3f; PathTo(Grid.FreePoint(Sees ? Rat.transform.position : last)); }
                    if (!Follow(1.5f * mul, dt) && Sees) Turn(ToRat, dt * 6f);
                    if (lostT > 2.2f) { mode = Mode.Look; t2 = 2.5f; path.Clear(); G.Bubble("Where did it go?..", transform, 1.95f, 1.8f); }
                    break;
                case Mode.Leaving:
                    sweep *= 0.95f;
                    if (plan == null && G.Stars >= OwnerStar) { mode = Mode.Patrol; path.Clear(); break; }
                    if (!Follow(0.95f, dt))
                    {
                        bool clean = planActive && !chasedThisVisit;
                        mode = Mode.Away; known = false; planActive = false; planStarted = false;
                        Show(false);
                        SetRoomLight(false);
                        G.Tasks.Flag("ownerLeft");
                        if (clean) G.Tasks.Flag("ownerClean");
                        return;
                    }
                    break;
            }

            if (mode != Mode.Leaving && mode != Mode.Chase && !planActive)
            {
                if (G.Stars < OwnerStar)
                {
                    lowT += dt;
                    if (lowT > 8f) { mode = Mode.Leaving; PathTo(door); G.Bubble("Must be nothing… Back to bed.", transform, 1.95f, 2f); }
                }
                else lowT = 0f;
            }

            if (flashlight)
            {
                flashlight.enabled = planActive && plan != null && !plan.light;
                flashlight.transform.localRotation = Quaternion.Euler(18f, sweep * Mathf.Rad2Deg, 0f);
            }

            if (Speed > 1.2f) Play("run", 0.15f);
            else if (Speed > 0.05f) Play("walk");
            else if (mode == Mode.Drink) Play("drink");
            else if (flashlight && flashlight.enabled) Play("flashlight_sweep");
            else Play(mode == Mode.Look ? "look_around" : "idle");

            float reach = 0.29f + (Rat.transform.position.y > 0.2f ? 0.32f : 0.1f);
            if (mode != Mode.Leaving && !(Rat.Hidden || Rat.InNest) && !Rat.Jumping && Rat.transform.position.y < 1.1f && dist < reach && G.GraceT <= 0f)
            {
                mode = Mode.Look; t2 = 2f; path.Clear(); seeT = 0f;
                if (anim) anim.Play("swat", 0.05f, true);
                G.Caught("WHACK! Slipper!", transform.position + Vector3.up * 2f);
            }
        }
    }
}
