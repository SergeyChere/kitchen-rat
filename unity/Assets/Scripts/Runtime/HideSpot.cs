using UnityEngine;

namespace KitchenRat
{
    /// <summary>A crack at the bottom of a wall: the rat is hidden while inside.</summary>
    public class HideSpot : Zone
    {
        public string id = "crack";

        public override void Enter(RatController rat)
        {
            rat.Hidden = true;
            GameManager.I.Report(Check.Hide, id);
        }

        public override void Exit(RatController rat) { rat.Hidden = false; }
    }
}
