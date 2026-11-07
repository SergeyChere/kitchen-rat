using UnityEngine;

namespace KitchenRat
{
    public enum FoodKind { Crumb, Cheese, Find }

    /// <summary>Something the rat picks up by walking over it: food for the nest, or a find (secret) that sets a flag.</summary>
    public class Food : MonoBehaviour
    {
        public FoodKind kind = FoodKind.Crumb;
        [Tooltip("Task tag: \"plate\", \"first\"… Tasks like 'Take the cheese from the plate' check it.")]
        public string id = "";
        [Tooltip("Invisible until the rat sniffs nearby.")]
        public bool hidden;
        [Tooltip("For finds: the flag reported when picked up (\"button\").")]
        public string flag = "";
        public string label = "";

        [System.NonSerialized] public bool carried;
        Renderer[] rends;

        public int Value => kind == FoodKind.Cheese ? 5 : kind == FoodKind.Crumb ? 1 : 0;

        void Awake() { rends = GetComponentsInChildren<Renderer>(); }
        void Start() { SetVisible(!hidden); }

        public void Reveal()
        {
            if (!hidden) return;
            hidden = false;
            SetVisible(true);
        }

        void SetVisible(bool v)
        {
            foreach (var r in rends) r.enabled = v;
        }

        void Update()
        {
            if (!carried && !hidden) transform.Rotate(0f, 30f * Time.deltaTime, 0f, Space.World);
        }
    }
}
