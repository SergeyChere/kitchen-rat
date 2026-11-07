using UnityEngine;

namespace KitchenRat
{
    /// <summary>Plays one looping clip forever (sleeping pups, idle decor characters).</summary>
    public class PlayClip : MonoBehaviour
    {
        public string clip = "idle";
        public float speed = 1f;

        void Start()
        {
            var p = GetComponent<ClipPlayer>();
            if (!p) return;
            p.Play(clip, 0f);
            p.Speed = speed;
        }
    }
}
