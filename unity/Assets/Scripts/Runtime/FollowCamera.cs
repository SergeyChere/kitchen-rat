using UnityEngine;

namespace KitchenRat
{
    /// <summary>Third-person orbit camera close to the floor. Mouse looks around, the wheel zooms, walls push it in.</summary>
    public class FollowCamera : MonoBehaviour
    {
        public Transform target;
        public float distance = 0.75f;
        public float minDistance = 0.3f;
        public float maxDistance = 1.8f;
        public float height = 0.12f;
        public float sensitivity = 2.5f;
        public float yaw;
        public float pitch = 16f;
        float current;

        void Start()
        {
            if (target) yaw = target.eulerAngles.y;
            current = distance;
        }

        void LateUpdate()
        {
            if (!target) return;
            if (Cursor.lockState == CursorLockMode.Locked)
            {
                var look = GameInput.Look;
                yaw += look.x * sensitivity;
                pitch = Mathf.Clamp(pitch - look.y * sensitivity, -20f, 70f);
                distance = Mathf.Clamp(distance - GameInput.Zoom * 0.12f, minDistance, maxDistance);
            }
            Vector3 focus = target.position + Vector3.up * height;
            Quaternion rot = Quaternion.Euler(pitch, yaw, 0f);
            Vector3 back = rot * Vector3.back;
            float want = distance;
            if (Physics.SphereCast(focus, 0.04f, back, out var hit, distance, RatController.Mask, QueryTriggerInteraction.Ignore))
                want = Mathf.Max(0.06f, hit.distance - 0.02f);
            current = want < current ? want : Mathf.Lerp(current, want, Time.deltaTime * 4f);
            transform.SetPositionAndRotation(focus + back * current, rot);
        }
    }
}
