using UnityEngine;

/// <summary>
/// Камера от третьего лица с управлением мышью (курсор захвачен, как в шутерах).
/// Не залезает в стены и мебель. В кат-сценах управляется скриптом (scripted = true).
/// </summary>
public class ThirdPersonCamera : MonoBehaviour
{
    public Transform target;
    public float distance = 0.78f;
    public float pivotHeight = 0.14f;
    [Tooltip("Чувствительность мыши")] public float sensitivity = 2f;
    public bool invertY = false;
    public float minPitch = -5f, maxPitch = 65f;
    public float collisionRadius = 0.03f;
    public float followSharpness = 12f;

    [HideInInspector] public float yaw = 45f, pitch = 22f;
    [HideInInspector] public bool inputEnabled;

    [Header("Кат-сцены")]
    [HideInInspector] public bool scripted;
    [HideInInspector] public Vector3 scriptedPos, scriptedLook;
    public float scriptedSharpness = 3f;

    /// <summary>Направление «вперёд» камеры по полу — для движения крысы.</summary>
    public Vector3 FlatForward { get { return Quaternion.Euler(0f, yaw, 0f) * Vector3.forward; } }

    void LateUpdate()
    {
        float dt = Time.deltaTime;
        if (scripted)
        {
            transform.position = Vector3.Lerp(transform.position, scriptedPos, 1f - Mathf.Exp(-scriptedSharpness * dt));
            LookAt(scriptedLook);
            return;
        }
        if (!target) return;

        if (inputEnabled && Cursor.lockState == CursorLockMode.Locked)
        {
            Vector2 d = GameInput.Look();
            yaw += d.x * sensitivity;
            pitch = Mathf.Clamp(pitch + (invertY ? d.y : -d.y) * sensitivity, minPitch, maxPitch);
        }

        Vector3 pivot;
        Vector3 want = Desired(out pivot);
        transform.position = Vector3.Lerp(transform.position, want, 1f - Mathf.Exp(-followSharpness * dt));
        LookAt(pivot);
    }

    Vector3 Desired(out Vector3 pivot)
    {
        pivot = target.position + Vector3.up * pivotHeight;
        Vector3 back = Quaternion.Euler(pitch, yaw, 0f) * Vector3.back;
        float d = Sight.SphereDistance(pivot, back, collisionRadius, distance);
        return pivot + back * Mathf.Max(0.1f, d - 0.01f);
    }

    void LookAt(Vector3 p)
    {
        Vector3 d = p - transform.position;
        if (d.sqrMagnitude > 1e-6f) transform.rotation = Quaternion.LookRotation(d);
    }

    /// <summary>Сразу поставить камеру за спину цели, без плавного перелёта.</summary>
    public void SnapNow()
    {
        if (!target) return;
        Vector3 pivot;
        transform.position = Desired(out pivot);
        LookAt(pivot);
    }
}
