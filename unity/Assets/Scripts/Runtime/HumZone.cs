using UnityEngine;

namespace KitchenRat
{
    /// <summary>A humming fridge or washer: inside it the rat's quiet footsteps can't be heard.</summary>
    public class HumZone : Zone
    {
        public override void Enter(RatController rat) { GameManager.I.InHum++; }
        public override void Exit(RatController rat) { GameManager.I.InHum = Mathf.Max(0, GameManager.I.InHum - 1); }
        protected override Color GizmoColor => new Color(0.4f, 0.8f, 1f, 0.5f);
    }
}
