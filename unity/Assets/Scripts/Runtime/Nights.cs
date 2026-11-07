using System.Collections.Generic;
using UnityEngine;

namespace KitchenRat
{
    /// <summary>Kinds of task checks, same as the prototype's levels.js: pick, deliver, surf, hide, knock, flag, keep, pickN.</summary>
    public enum Check { Pick, Deliver, Surf, Hide, Knock, Flag, Keep, PickN }

    public class TaskDef
    {
        public string text, hint;
        public Check check;
        public string arg;
        public int n;
        public int reveal; // side tasks: shown after this many chain steps

        public TaskDef(string text, string hint, Check check, string arg = null, int n = 0, int reveal = 0)
        {
            this.text = text; this.hint = hint; this.check = check; this.arg = arg; this.n = n; this.reveal = reveal;
        }
    }

    public struct FoodSpot
    {
        public FoodKind kind;
        public float x, y; // prototype room coordinates, cm (x → east, y → south)
        public string id;
        public bool hidden;
        public string flag;
        public FoodSpot(FoodKind kind, float x, float y, string id = "", bool hidden = false, string flag = "")
        {
            this.kind = kind; this.x = x; this.y = y; this.id = id; this.hidden = hidden; this.flag = flag;
        }
    }

    public class NightDef
    {
        public string id, name, blurb, startTitle, startSub, teaser;
        public int number, goal;
        public float seconds;
        public float width = 960f, depth = 600f;
        public string goalText = "Fill the nest";
        public List<FoodSpot> spots = new List<FoodSpot>();
        public int randomCrumbs, randomCheese;
        public TaskDef[] chain = new TaskDef[0], side = new TaskDef[0], secret = new TaskDef[0];
    }

    /// <summary>Night data ported from game/js/levels.js. Add the other 19 nights here as they are rebuilt.</summary>
    public static class Nights
    {
        /// <summary>Prototype room coordinates (cm, origin at the north-west corner) → Unity metres (origin in the middle of the room).</summary>
        public static Vector3 World(float x, float y, float h = 0f, float width = 960f, float depth = 600f)
            => new Vector3((x - width / 2f) / 100f, h / 100f, (depth / 2f - y) / 100f);

        public static NightDef Get(string id)
        {
            switch (id)
            {
                default: return Kitchen();
            }
        }

        public static NightDef Kitchen()
        {
            var n = new NightDef
            {
                id = "kitchen", number = 1, name = "The Kitchen", goal = 15, seconds = 900f,
                blurb = "Your first night out. Nobody is home.",
                startTitle = "Your first night out",
                startSub = "Nobody is home. Follow the tasks in the bottom-left corner.",
                teaser = "The living room. The cat sleeps there, so you’ll have to be quiet.",
                randomCrumbs = 10, randomCheese = 3,
            };
            n.spots.Add(new FoodSpot(FoodKind.Crumb, 585, 548, "first"));
            n.spots.Add(new FoodSpot(FoodKind.Cheese, 680, 432, "plate"));
            n.spots.Add(new FoodSpot(FoodKind.Cheese, 116, 30, "bread", hidden: true));
            n.spots.Add(new FoodSpot(FoodKind.Cheese, 232, 470));
            n.spots.Add(new FoodSpot(FoodKind.Find, 895, 198, "button", flag: "button"));
            n.chain = new[]
            {
                new TaskDef("Pick up the crumb by the table", "Walk over food to pick it up. Move with WASD, look around with the mouse.", Check.Pick, "first"),
                new TaskDef("Take it home to the nest", "The nest is behind the mouse hole in the south wall.", Check.Deliver),
                new TaskDef("Jump onto a chair", "Walk up to a chair and face it. When the yellow ring appears, press Space.", Check.Surf, "chair"),
                new TaskDef("Climb from the chair onto the table", "From the chair, face the table and press Space when the ring appears.", Check.Surf, "table"),
                new TaskDef("Take the cheese from the plate", "A cheese is worth 5 crumbs. Careful: walk slowly past the mug on the edge.", Check.Pick, "plate"),
                new TaskDef("Bring the cheese home", "Walk to the edge of the table and press Space to jump down, then head for the nest.", Check.Deliver, "plate"),
                new TaskDef("Sneak across the foil without a sound", "Hold Ctrl or press C to sneak. Walking on foil makes it crinkle loudly.", Check.Flag, "foilSneak"),
                new TaskDef("Hide in a crack in the wall", "Cracks are dark gaps at the bottom of the walls.", Check.Hide, "crack"),
                new TaskDef("Stand up and sniff", "Hold E or the right mouse button. A thin trail of scent leads to the nearest food.", Check.Flag, "sniffed"),
                new TaskDef("Find the cheese hidden by the bread box", "The bread box is up on the counter. Climb the stool, jump to the counter and sniff there.", Check.Pick, "bread"),
                new TaskDef("Climb onto the kitchen island", "It’s too high to reach from the floor. Use the cardboard box next to it as a step.", Check.Surf, "island"),
                new TaskDef("Push the apple off the island", "Walk up to the apple and press F. Falling things make noise.", Check.Knock, "apple"),
            };
            n.side = new[]
            {
                new TaskDef("Leave the mug on the table", null, Check.Keep, "cup", reveal: 3),
                new TaskDef("Carry 3 pieces home at once", null, Check.Flag, "full", reveal: 2),
            };
            n.secret = new[] { new TaskDef("Find the shiny button", null, Check.Flag, "button") };
            return n;
        }
    }
}
