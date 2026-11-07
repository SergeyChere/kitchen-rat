using UnityEngine;

namespace KitchenRat
{
    /// <summary>A box-shaped area (local space, centred on the transform, bottom at y = 0). The game checks the rat against it every frame.</summary>
    public class Zone : MonoBehaviour
    {
        public Vector3 size = new Vector3(0.4f, 0.3f, 0.4f);
        [System.NonSerialized] public bool inside;

        public bool Contains(Vector3 p)
        {
            var l = transform.InverseTransformPoint(p);
            return Mathf.Abs(l.x) <= size.x * 0.5f && Mathf.Abs(l.z) <= size.z * 0.5f && l.y >= -0.05f && l.y <= size.y;
        }

        /// <summary>Is the point inside the zone's footprint, grown by margin (height ignored)?</summary>
        public bool ContainsXZ(Vector3 p, float margin)
        {
            var l = transform.InverseTransformPoint(p);
            return Mathf.Abs(l.x) <= size.x * 0.5f + margin && Mathf.Abs(l.z) <= size.z * 0.5f + margin;
        }

        public virtual void Enter(RatController rat) { }
        public virtual void Stay(RatController rat, float dt) { }
        public virtual void Exit(RatController rat) { }

        protected virtual Color GizmoColor => new Color(0.3f, 1f, 0.5f, 0.5f);

        void OnDrawGizmos()
        {
            Gizmos.color = GizmoColor;
            Gizmos.matrix = transform.localToWorldMatrix;
            Gizmos.DrawWireCube(new Vector3(0, size.y / 2, 0), size);
        }
    }
}
