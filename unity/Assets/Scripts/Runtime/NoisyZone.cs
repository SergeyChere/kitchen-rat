using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// Things that make noise under the paws, from the prototype's NOISY table: foil, floorboards, bags, puddles,
    /// glasses, balloons… mode: walk (any non-sneaking step), step (any step, even sneaking), run (only running),
    /// land (landing on it after a jump), landrun (landing or running). Foil also sets a flag when crossed sneaking.
    /// </summary>
    public class NoisyZone : Zone
    {
        public string kind = "foil";
        public string mode = "walk";
        public string sound = "Crinkle!";
        [Tooltip("How far the noise carries, m.")]
        public float radius = 1.5f;
        [Tooltip("How much it disturbs a sleeping cat at point-blank range (1 wakes it).")]
        public float amount = 0.4f;
        public bool big;
        public float cooldown = 0.45f;
        public bool once;
        [Tooltip("Hidden when it goes off (a balloon pops).")]
        public GameObject hideWhenUsed;
        public string sneakFlag = "";
        public float passDistance = 0.4f;

        [System.NonSerialized] public bool used;
        float cd, sneaked, hintT;
        bool loud;

        bool OnIt(RatController rat) => !rat.Jumping && Mathf.Abs(rat.transform.position.y - transform.position.y) < 0.06f;

        public override void Enter(RatController rat)
        {
            sneaked = 0f;
            loud = false;
        }

        public override void Stay(RatController rat, float dt)
        {
            cd -= dt;
            hintT -= dt;
            if (!OnIt(rat) || !rat.Moving) return;
            bool trigger = mode == "step" || (mode == "run" || mode == "landrun" ? rat.Running : mode == "walk" && !rat.Sneaking);
            if (!trigger)
            {
                if (rat.Sneaking) sneaked += rat.MoveSpeed * dt;
                return;
            }
            loud = true;
            Trigger(rat);
        }

        /// <summary>Called by the game when the rat lands from a jump while inside.</summary>
        public void OnLanded(RatController rat)
        {
            if ((mode == "land" || mode == "landrun") && OnIt(rat)) Trigger(rat);
        }

        void Trigger(RatController rat)
        {
            if (cd > 0f || (once && used)) return;
            cd = cooldown;
            used = true;
            GameManager.I.Noise(rat.transform.position, radius, sound, big, amount);
            if (hideWhenUsed) hideWhenUsed.SetActive(false);
            if (!string.IsNullOrEmpty(sneakFlag) && hintT <= 0f && GameManager.I.Tasks.FlagValue(sneakFlag) == 0)
            {
                hintT = 6f;
                GameManager.I.Toast("Too loud! Hold Ctrl (or press C) and sneak across.");
            }
        }

        public override void Exit(RatController rat)
        {
            if (!loud && sneaked >= passDistance && !string.IsNullOrEmpty(sneakFlag)) GameManager.I.Tasks.SetFlag(sneakFlag);
        }

        /// <summary>Settings for a prototype noisy kind (radius in m).</summary>
        public void Configure(string k)
        {
            kind = k;
            switch (k)
            {
                case "foil": Set("walk", "Crinkle!", 1.5f, 0.4f, 0.45f); sneakFlag = "foilSneak"; break;
                case "plate": Set("landrun", "Clink!", 2.3f, 0.6f, 1.2f); break;
                case "sofa": Set("land", "Scritch!", 1.9f, 0.45f, 1f); break;
                case "remote": Set("step", "The TV turned on!", 6.5f, 1f, 1f, true, true); break;
                case "squeaky": Set("step", "Squeak!", 2.5f, 0.7f, 2.5f); break;
                case "board": Set("walk", "Creak…", 1.8f, 0.35f, 0.9f); break;
                case "bag": Set("walk", "Rustle!", 1.6f, 0.35f, 0.45f); break;
                case "grain": Set("walk", "Crunch", 1.4f, 0.3f, 0.5f); break;
                case "puddle": Set("walk", "Splash!", 1.6f, 0.35f, 0.6f); break;
                case "cord": Set("step", "Bzzt!", 2.1f, 0.5f, 3f); break;
                case "washer": Set("step", "The washing machine started!", 3.2f, 0.3f, 1f, false, true); break;
                case "hanger": Set("walk", "Clink clink", 1.8f, 0.35f, 0.8f); break;
                case "balloon": Set("step", "POP!", 4.2f, 0.8f, 1f, true, true); break;
                case "confetti": Set("walk", "Rustle", 1.4f, 0.3f, 0.5f); break;
                case "glasses": Set("walk", "Clink!", 2.2f, 0.5f, 0.9f); break;
                case "litter": Set("walk", "Scratch scratch", 1.2f, 0.2f, 0.8f); break;
                case "dock": Set("step", "Beep! Charging…", 2.6f, 0.4f, 3f); break;
                case "pipe": Set("run", "Bwonng!", 3.6f, 0.5f, 1f); break;
                case "lego": Set("walk", "Ouch! Lego!", 1.9f, 0.45f, 0.8f); break;
                case "musicbox": Set("step", "♪ Twinkle twinkle… ♪", 3f, 0.6f, 5f); break;
                case "nightlight": Set("walk", "Click! The night light is on", 1.6f, 0.25f, 6f); break;
                case "bottles": Set("walk", "Clatter!", 2.4f, 0.5f, 0.8f); break;
                case "popper": Set("step", "BANG! A party popper!", 4.5f, 0.85f, 1f, true, true); break;
            }
        }

        void Set(string m, string s, float r, float a, float c, bool b = false, bool o = false)
        {
            mode = m; sound = s; radius = r; amount = a; cooldown = c; big = b; once = o;
        }

        protected override Color GizmoColor => new Color(1f, 0.9f, 0.2f, 0.6f);
    }
}
