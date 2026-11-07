using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// Food the rat picks up by walking over it, or a find (secret) that sets a flag. Like the prototype:
    /// a crumb weighs 1 and is worth 1, a cheese weighs 2 and is worth 5, big food (sausage, chicken…) weighs 3,
    /// is worth 6 and has to be dragged. The rat carries up to weight 3.
    /// </summary>
    public class Food : MonoBehaviour
    {
        public static readonly string[] BigTypes = { "sausage", "chicken", "pizza", "cake", "potato", "fat", "biscuit", "salami" };

        public string type = "crumb";
        [Tooltip("Task tag: \"plate\", \"first\"… Tasks like 'Take the cheese from the plate' check it.")]
        public string id = "";
        [Tooltip("Invisible until the rat sniffs nearby.")]
        public bool hidden;
        public bool poison;
        [Tooltip("A find (secret): sets the flag with its kind when picked up, worth nothing.")]
        public bool isFind;
        public string label = "";

        [System.NonSerialized] public bool carried;
        [System.NonSerialized] public float revealT;
        Renderer[] rends;
        bool shown = true;

        public bool Big => System.Array.IndexOf(BigTypes, type) >= 0;
        public bool IsCheese => !isFind && type != "crumb";
        public int Weight => isFind ? 0 : Big ? 3 : type == "crumb" ? 1 : 2;
        public int Value => isFind || poison ? 0 : Big ? 6 : type == "crumb" ? 1 : 5;
        public bool Visible => shown;

        void Awake() { rends = GetComponentsInChildren<Renderer>(); }

        public void SetVisible(bool v)
        {
            if (v == shown) return;
            shown = v;
            foreach (var r in rends) if (r) r.enabled = v;
        }

        public void MakePoison()
        {
            poison = true;
            foreach (var r in rends)
                foreach (var m in r.materials) m.color = Color.Lerp(m.color, new Color(0.45f, 0.9f, 0.3f), 0.65f);
        }

        void Update()
        {
            if (revealT > 0f) revealT -= Time.deltaTime;
            if (!carried && shown) transform.Rotate(0f, 30f * Time.deltaTime, 0f, Space.World);
        }

        /// <summary>Model path in Assets/Art for a prototype food type.</summary>
        public static string ModelFor(string type)
        {
            switch (type)
            {
                case "crumb": return "food/crumb";
                case "sausage": case "salami": return "food/sausage";
                case "chicken": return "food/chicken_leg";
                case "pizza": return "food/pizza_slice";
                case "cake": return "food/cake_slice";
                case "potato": return "food/potato";
                case "fat": return "food/lard";
                case "biscuit": case "treat": return "food/dog_biscuit";
                case "cookie": return "food/cookie";
                case "kibble": return "food/kibble";
                case "rusk": return "food/rusk";
                default: return "food/cheese";
            }
        }
    }
}
