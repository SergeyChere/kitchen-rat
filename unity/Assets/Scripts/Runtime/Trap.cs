using UnityEngine;

namespace KitchenRat
{
    /// <summary>A mousetrap on the floor. Sniffing reveals it; stepping on it snaps (a life); something falling on it disarms it.</summary>
    public class Trap : MonoBehaviour
    {
        public bool hidden;
        [System.NonSerialized] public bool sprung, found;
        Transform bar;
        Renderer[] rends;
        float barAngle;

        void Awake()
        {
            rends = GetComponentsInChildren<Renderer>();
            bar = transform.Find("bar");
            if (!bar) foreach (var t in GetComponentsInChildren<Transform>()) if (t.name.StartsWith("bar")) bar = t;
        }

        void Start() { SetVisible(!hidden); }

        public void Reveal()
        {
            hidden = false;
            found = true;
            SetVisible(true);
        }

        void SetVisible(bool v) { foreach (var r in rends) r.enabled = v; }

        public void Spring()
        {
            if (sprung) return;
            sprung = true;
            SetVisible(true);
        }

        void Update()
        {
            if (!sprung || !bar || barAngle >= 170f) return;
            float step = Mathf.Min(170f - barAngle, 1400f * Time.deltaTime);
            barAngle += step;
            bar.Rotate(-step, 0f, 0f, Space.Self);
        }
    }
}
