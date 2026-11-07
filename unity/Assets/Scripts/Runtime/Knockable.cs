using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// A cup, jar, apple… the rat can push off a surface with F. A "trap" one falls by itself when the rat walks
    /// past without sneaking. The crash is a big noise: it lures the cat and can disarm a mousetrap it lands on.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class Knockable : MonoBehaviour
    {
        public string kind = "cup";
        public bool trap;
        public Vector3 pushDir = Vector3.forward;
        [Tooltip("Food type that appears where it lands (a box of cookies…).")]
        public string spawn = "";
        [System.NonSerialized] public bool knocked;
        bool landed;
        Rigidbody rb;

        public string Sound
        {
            get
            {
                switch (kind)
                {
                    case "cup": case "glass": return "Clink!";
                    case "vase": return "Crash!";
                    case "jar": case "bottle": return "Bang!";
                    case "can": case "spoon": return "Clang!";
                    case "carton": return "Thump!";
                    case "ball": return "Bonk!";
                    default: return "Thud!";
                }
            }
        }

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
            GameManager.I.Tasks.knocked.Add(kind);
        }

        void OnCollisionEnter(Collision c)
        {
            if (!knocked || landed || c.relativeVelocity.magnitude < 1.2f) return;
            landed = true;
            GameManager.I.KnockLanded(this, transform.position);
        }
    }
}
