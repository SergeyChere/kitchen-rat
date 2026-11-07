using UnityEngine;

namespace KitchenRat
{
    /// <summary>A hiding spot on the floor: a crack in the wall, or the space under a table, chair, sofa or shelf.
    /// The rat is hidden inside; the cat and the owner can't walk in.</summary>
    public class HideSpot : Zone
    {
        [Tooltip("crack, table, chair, sofa, shelf… Tasks like 'Hide in a crack' check it.")]
        public string id = "crack";

        public override void Enter(RatController rat) { rat.EnterHide(this); }
        public override void Exit(RatController rat) { rat.ExitHide(this); }
    }
}
