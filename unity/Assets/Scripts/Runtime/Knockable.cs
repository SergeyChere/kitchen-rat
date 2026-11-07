using UnityEngine;

namespace KitchenRat
{
    /// <summary>A mug, jar or apple the rat can push off with F. A trap one falls by itself when the rat walks past without sneaking.</summary>
    [RequireComponent(typeof(Rigidbody))]
    public class Knockable : MonoBehaviour
    {
        public string kind = "cup";
        public bool trap;
        public Vector3 pushDir = Vector3.forward;
        [System.NonSerialized] public bool knocked;
        bool crashed;
        Rigidbody rb;

        void Awake()
        {
            rb = GetComponent<Rigidbody>();
            rb.isKinematic = true;
        }

        public void Knock(Vector3 dir)
        {
            if (knocked) return;
            knocked = true;
            rb.isKinematic = false;
            dir.y = 0f;
            rb.AddForce((dir.normalized * 0.9f + Vector3.up * 0.5f) * rb.mass, ForceMode.Impulse);
            rb.AddTorque(Random.insideUnitSphere * 0.01f, ForceMode.Impulse);
            GameManager.I.Report(Check.Knock, kind);
        }

        void OnCollisionEnter(Collision c)
        {
            if (!knocked || crashed || c.relativeVelocity.magnitude < 1.2f) return;
            crashed = true;
            GameManager.I.Noise(transform.position, 1f, kind == "apple" ? "Thud!" : "Crash!");
        }
    }
}
