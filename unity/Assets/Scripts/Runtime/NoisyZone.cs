using UnityEngine;

namespace KitchenRat
{
    /// <summary>Foil, squeaky floorboards…: loud unless the rat sneaks. Crossing it fully while sneaking raises a flag for tasks.</summary>
    public class NoisyZone : Zone
    {
        public string sound = "Crinkle!";
        public string sneakFlag = "foilSneak";
        public float passDistance = 0.45f;
        float sneaked;
        bool clean;
        float toastCooldown;

        public override void Enter(RatController rat)
        {
            sneaked = 0f;
            clean = true;
        }

        public override void Stay(RatController rat, float dt)
        {
            toastCooldown -= dt;
            if (!rat.Moving) return;
            if (rat.Sneaking) sneaked += rat.MoveSpeed * dt;
            else
            {
                clean = false;
                rat.AddNoise(1f);
                if (toastCooldown <= 0f)
                {
                    GameManager.I.Toast(sound + " Sneak (Ctrl or C) to cross quietly.");
                    toastCooldown = 3f;
                }
            }
        }

        public override void Exit(RatController rat)
        {
            if (clean && sneaked >= passDistance && !string.IsNullOrEmpty(sneakFlag)) GameManager.I.Report(Check.Flag, sneakFlag);
        }

        protected override Color GizmoColor => new Color(1f, 0.9f, 0.2f, 0.6f);
    }
}
