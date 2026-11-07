using UnityEngine;

/// <summary>
/// Кот: патрулирует по точкам, видит конусом, слышит бег, гонится и ищет.
/// Модель смотрит вдоль +Z.
/// </summary>
[RequireComponent(typeof(CharacterController))]
public class CatAI : MonoBehaviour
{
    public enum Mode { Patrol, Investigate, Chase, Search }

    [Header("Маршрут")]
    public Transform[] waypoints;
    public int startWaypoint = 3;

    [Header("Скорости (м/с)")]
    public float patrolSpeed = 0.68f;
    public float investigateSpeed = 0.95f;
    public float chaseSpeed = 1.72f;

    [Header("Чувства")]
    public float viewDistance = 2.3f;
    [Tooltip("Половина угла обзора, градусы")] public float viewHalfAngle = 36f;
    [Tooltip("Ближе этого кот замечает крысу даже сзади")] public float nearSense = 0.34f;
    public float hearRadius = 1.7f;
    public float catchDistance = 0.3f;
    public float eyeHeight = 0.3f;

    [Header("Части модели")]
    public Transform[] legs;
    public Transform tailPivot;
    public Renderer[] eyeRenderers;
    public Color calmEyes = new Color(0.6f, 0.88f, 0.42f);
    public Color angryEyes = new Color(1f, 0.85f, 0.3f);

    public Mode CurrentMode { get; private set; }
    public float Alert { get; private set; }
    public bool SeesRat { get; private set; }

    CharacterController cc;
    int wp;
    float lostT, searchT, step, vy;
    Vector3 lastSeen, startPos;
    Quaternion startRot;

    void Awake()
    {
        cc = GetComponent<CharacterController>();
        startPos = transform.position;
        startRot = transform.rotation;
    }

    static Vector3 Flat(Vector3 v) { v.y = 0f; return v; }

    public void ResetCat()
    {
        cc.enabled = false;
        transform.SetPositionAndRotation(startPos, startRot);
        cc.enabled = true;
        CurrentMode = Mode.Patrol;
        Alert = 0f;
        wp = waypoints.Length > 0 ? startWaypoint % waypoints.Length : 0;
    }

    /// <summary>Крыса шумит рядом — кот идёт проверить.</summary>
    public void Hear(Vector3 pos)
    {
        if (CurrentMode == Mode.Chase) return;
        if (Flat(pos - transform.position).magnitude > hearRadius) return;
        CurrentMode = Mode.Investigate;
        lastSeen = pos;
        Alert = Mathf.Max(Alert, 0.4f);
    }

    public void AfterCatch()
    {
        CurrentMode = Mode.Search;
        searchT = 1.5f;
        Alert = 0.3f;
    }

    int NearestWaypoint()
    {
        int best = 0; float bd = float.MaxValue;
        for (int i = 0; i < waypoints.Length; i++)
        {
            float d = Flat(waypoints[i].position - transform.position).sqrMagnitude;
            if (d < bd) { bd = d; best = i; }
        }
        return best;
    }

    /// <summary>Один шаг ИИ. Возвращает true, если кот поймал крысу.</summary>
    public bool Tick(float dt, RatController rat)
    {
        Vector3 toRat = Flat(rat.transform.position - transform.position);
        float dist = toRat.magnitude;
        bool inCone = dist < viewDistance && Vector3.Angle(transform.forward, toRat) < viewHalfAngle;
        Vector3 eye = transform.position + Vector3.up * eyeHeight;
        SeesRat = !rat.Hidden && (inCone || dist < nearSense) && Sight.Clear(eye, rat.transform.position + Vector3.up * 0.06f);

        if (SeesRat)
        {
            Alert += dt * (1.4f + (1f - dist / viewDistance) * 3f);
            lastSeen = rat.transform.position;
        }
        else if (CurrentMode != Mode.Chase) Alert -= dt * 0.5f;
        Alert = Mathf.Clamp01(Alert);

        if (Alert >= 1f && CurrentMode != Mode.Chase) { CurrentMode = Mode.Chase; lostT = 0f; }
        else if (Alert > 0.35f && SeesRat && CurrentMode == Mode.Patrol) CurrentMode = Mode.Investigate;

        Vector3 target = transform.position;
        float speed = 0f;
        switch (CurrentMode)
        {
            case Mode.Chase:
                if (SeesRat) { lostT = 0f; target = rat.transform.position; }
                else { lostT += dt; target = lastSeen; }
                speed = chaseSpeed;
                if (lostT > 1.3f) { CurrentMode = Mode.Search; searchT = 2.2f; Alert = 0.6f; }
                break;
            case Mode.Investigate:
                target = lastSeen; speed = investigateSpeed;
                if (Flat(target - transform.position).magnitude < 0.2f) { CurrentMode = Mode.Search; searchT = 1.8f; }
                break;
            case Mode.Search:
                searchT -= dt;
                transform.Rotate(0f, dt * 137f, 0f);
                if (searchT <= 0f) { CurrentMode = Mode.Patrol; Alert = 0f; wp = NearestWaypoint(); }
                break;
            default:
                if (waypoints.Length == 0) break;
                target = waypoints[wp].position; speed = patrolSpeed;
                if (Flat(target - transform.position).magnitude < 0.12f) wp = (wp + 1) % waypoints.Length;
                break;
        }

        vy = cc.isGrounded ? -0.5f : vy - 9.8f * dt;
        float actual = 0f;
        Vector3 dir = Flat(target - transform.position);
        if (speed > 0f && dir.sqrMagnitude > 1e-4f)
        {
            dir.Normalize();
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(dir), Mathf.Min(1f, dt * 7f));
            Vector3 before = transform.position;
            cc.Move((dir * speed + Vector3.up * vy) * dt);
            actual = Flat(transform.position - before).magnitude / Mathf.Max(dt, 1e-4f);
            // застрял в погоне — пробуем обойти боком
            if (CurrentMode == Mode.Chase && actual < speed * 0.25f)
                cc.Move(new Vector3(-dir.z, 0f, dir.x) * speed * dt);
        }
        else cc.Move(Vector3.up * vy * dt);

        step += dt * actual * 8f;
        return !rat.Hidden && dist < catchDistance;
    }

    void LateUpdate()
    {
        for (int i = 0; i < legs.Length; i++)
            legs[i].localRotation = Quaternion.Euler(Mathf.Sin(step + (i % 2 == 0 ? 0f : Mathf.PI)) * 28f, 0f, 0f);
        if (tailPivot) tailPivot.localRotation = Quaternion.Euler(0f, Mathf.Sin(Time.time * 2f + step * 0.3f) * 28f, 0f);

        Color c = CurrentMode == Mode.Chase ? angryEyes : calmEyes;
        foreach (var r in eyeRenderers)
        {
            if (!r) continue;
            r.material.color = c;
            if (r.material.HasProperty("_EmissionColor")) r.material.SetColor("_EmissionColor", c * 1.5f);
        }
    }
}
