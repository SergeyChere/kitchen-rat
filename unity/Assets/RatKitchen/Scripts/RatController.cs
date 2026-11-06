using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Крыса-мама: движение относительно камеры, бег (шумный), перенос еды, анимация из примитивов.
/// Модель смотрит вдоль +Z.
/// </summary>
[RequireComponent(typeof(CharacterController))]
public class RatController : MonoBehaviour
{
    [Header("Движение")]
    public float walkSpeed = 1.25f;
    public float sprintSpeed = 1.95f;
    [Tooltip("Насколько медленнее с каждой единицей груза")] public float carrySlowdown = 0.13f;
    public float pickupRadius = 0.18f;
    public float noiseInterval = 0.35f;

    [Header("Части модели")]
    public Transform body;
    public Transform head;
    public Transform tailPivot;
    public Transform mouth;
    public Transform[] eyes;

    /// <summary>0 — спит, 1 — проснулась. Меняется в кат-сцене.</summary>
    [HideInInspector] public float wake = 1f;

    public CharacterController Cc { get; private set; }
    public readonly List<FoodItem> carried = new List<FoodItem>();
    public bool Hidden { get; private set; }
    public bool Sprinting { get; private set; }

    float step, noiseTimer, vy;
    Vector3 bodyScale, bodyPos, headPos;
    Vector3[] eyeScales;

    void Awake()
    {
        Cc = GetComponent<CharacterController>();
        bodyScale = body.localScale;
        bodyPos = body.localPosition;
        headPos = head.localPosition;
        eyeScales = new Vector3[eyes.Length];
        for (int i = 0; i < eyes.Length; i++) eyeScales[i] = eyes[i].localScale;
    }

    public int CarryWeight
    {
        get { int w = 0; foreach (var f in carried) w += f.weight; return w; }
    }

    /// <summary>Мгновенно переставить крысу. enableController=false — для кат-сцен.</summary>
    public void Teleport(Vector3 pos, float yaw, bool enableController = true)
    {
        Cc.enabled = false;
        transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yaw, 0f));
        Cc.enabled = enableController;
        vy = 0f;
    }

    /// <summary>Шаг анимации, когда крысу двигает кат-сцена.</summary>
    public void ScriptedStep(float amount) { step += amount; }

    /// <summary>Вызывается GameManager каждый кадр во время игры.</summary>
    public void Tick(float dt, Vector3 camForward)
    {
        Vector2 inp = GameInput.Move();
        Vector3 right = new Vector3(camForward.z, 0f, -camForward.x);
        Vector3 move = camForward * inp.y + right * inp.x;
        if (move.sqrMagnitude > 1f) move.Normalize();
        bool moving = move.sqrMagnitude > 0.01f;

        Sprinting = GameInput.Sprint() && moving;
        float spd = (Sprinting ? sprintSpeed : walkSpeed) * (1f - carrySlowdown * CarryWeight);

        vy = Cc.isGrounded ? -0.5f : vy - 9.8f * dt;
        Cc.Move((move * spd + Vector3.up * vy) * dt);

        if (moving)
        {
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(move), dt * 14f);
            step += dt * spd * 15f;
        }

        if (Sprinting)
        {
            noiseTimer -= dt;
            if (noiseTimer <= 0f)
            {
                noiseTimer = noiseInterval;
                GameManager.I.OnRatNoise(transform.position);
            }
        }

        Hidden = HideZone.Any(transform.position + Vector3.up * 0.05f) || GameManager.I.InHole(transform.position);
    }

    void LateUpdate()
    {
        float w = Mathf.Clamp01(wake);

        // поза сна: приплюснутая, голова опущена, глаза закрыты
        Vector3 sleepScale = new Vector3(bodyScale.x * 1.2f, bodyScale.y * 0.75f, bodyScale.z * 1.1f);
        body.localScale = Vector3.Lerp(sleepScale, bodyScale, w);
        float bob = w >= 1f ? Mathf.Abs(Mathf.Sin(step * 2f)) * 0.012f : (w - 1f) * 0.02f;
        body.localPosition = bodyPos + Vector3.up * bob;
        head.localPosition = Vector3.Lerp(headPos + new Vector3(0f, -0.03f, 0f), headPos, w);
        head.localRotation = Quaternion.Euler(Mathf.Lerp(15f, 0f, w), 0f, 0f);
        for (int i = 0; i < eyes.Length; i++)
        {
            Vector3 s = eyeScales[i];
            if (w < 0.5f) s.y *= 0.15f;
            eyes[i].localScale = s;
        }

        if (tailPivot) tailPivot.localRotation = Quaternion.Euler(0f, Mathf.Sin(step) * 25f, 0f);

        // еда в зубах
        int n = carried.Count;
        for (int i = 0; i < n; i++)
        {
            var t = carried[i].transform;
            t.localPosition = new Vector3((i - (n - 1) * 0.5f) * 0.06f, 0f, i * 0.02f);
            t.localRotation = Quaternion.identity;
        }
    }
}
