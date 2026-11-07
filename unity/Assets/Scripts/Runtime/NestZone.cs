using UnityEngine;

namespace KitchenRat
{
    /// <summary>The nest behind the mouse hole. Food carried in here is delivered.</summary>
    public class NestZone : Zone
    {
        public override void Enter(RatController rat) { rat.InNest = true; }
        public override void Exit(RatController rat) { rat.InNest = false; }

        public override void Stay(RatController rat, float dt)
        {
            if (rat.carried.Count > 0 && !rat.Jumping && GameManager.I.Playing) GameManager.I.Deliver();
        }

        protected override Color GizmoColor => new Color(1f, 0.7f, 0.3f, 0.6f);
    }
}
