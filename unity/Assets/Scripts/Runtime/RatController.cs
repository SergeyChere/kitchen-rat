using System;
using System.Collections.Generic;
using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// The mother rat: walk / run / sneak relative to the camera, sniff, and the prototype's aimed jump —
    /// face a higher surface (or an edge) and a yellow ring shows where Space will land her.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class RatController : MonoBehaviour
    {
        public const int IgnoreLayer = 2; // "Ignore Raycast": the rat itself
        public const int Mask = ~(1 << IgnoreLayer);

        [Header("Speed, m/s")]
        public float walkSpeed = 0.9f;
        public float runSpeed = 1.9f;
        public float sneakSpeed = 0.4f;
        public float turnSpeed = 600f;
        public float gravity = 12f;

        [Header("Jumping, m")]
        public float maxJumpUp = 0.62f;
        public float maxJumpReach = 0.9f;

        [Header("Parts")]
        public ClipPlayer anim;
        public Transform mouth;
        public Transform marker;
        public Transform cameraRig;
        public int capacity = 3;

        public bool Frozen { get; set; } = true;
        public bool Sneaking { get; private set; }
        public bool Running { get; private set; }
        public bool Sniffing { get; private set; }
        public bool Hidden { get; set; }
        public bool InNest { get; set; }
        public bool Jumping => jumping;
        public float MoveSpeed { get; private set; }
        public bool Moving => MoveSpeed > 0.05f;
        public float Noise { get; private set; }
        public string SurfaceId { get; private set; } = "floor";
        public bool HasJumpTarget => hasTarget;
        public event Action<string> SurfaceChanged;
        public readonly List<Food> carried = new List<Food>();

        CharacterController cc;
        float vy;
        bool sneakToggle;
        bool jumping, jumpUp;
        Vector3 jumpFrom, jumpTo;
        float jumpT, jumpDur, landT;
        bool hasTarget, targetUp;
        Vector3 target;

        void Awake() { cc = GetComponent<CharacterController>(); }

        public void AddNoise(float v) { Noise = Mathf.Max(Noise, v); }

        public void Carry(Food f)
        {
            carried.Add(f);
            f.carried = true;
            f.transform.SetParent(mouth ? mouth : transform, true);
            int i = carried.Count - 1;
            f.transform.localPosition = new Vector3(0f, i * 0.015f, -i * 0.03f);
            f.transform.localRotation = Quaternion.identity;
        }

        void Update()
        {
            float dt = Time.deltaTime;
            Noise = Mathf.MoveTowards(Noise, 0f, dt * 1.5f);
            if (Frozen)
            {
                MoveSpeed = 0f;
                Sniffing = false;
                ShowMarker(false);
                PlayAnim();
                return;
            }
            if (jumping)
            {
                TickJump(dt);
                PlayAnim();
                return;
            }

            Vector2 mv = GameInput.Move;
            if (GameInput.SneakToggle) sneakToggle = !sneakToggle;
            Sniffing = GameInput.Sniff && cc.isGrounded;
            Running = GameInput.Run && mv.sqrMagnitude > 0.01f && !Sniffing;
            if (Running) sneakToggle = false;
            Sneaking = !Running && (GameInput.SneakHeld || sneakToggle);

            Vector3 fwd = transform.forward;
            if (cameraRig)
            {
                var f = Vector3.ProjectOnPlane(cameraRig.forward, Vector3.up);
                if (f.sqrMagnitude > 1e-4f) fwd = f.normalized;
            }
            Vector3 right = Vector3.Cross(Vector3.up, fwd);
            Vector3 dir = Sniffing ? Vector3.zero : fwd * mv.y + right * mv.x;
            float spd = Running ? runSpeed : Sneaking ? sneakSpeed : walkSpeed;
            if (carried.Count > 0) spd *= 0.85f;
            if (dir.sqrMagnitude > 1e-4f)
                transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(dir), turnSpeed * dt);

            if (cc.isGrounded && vy < 0f) vy = -0.5f;
            vy -= gravity * dt;
            Vector3 before = transform.position;
            cc.Move((dir * spd + Vector3.up * vy) * dt);
            Vector3 moved = transform.position - before;
            moved.y = 0f;
            MoveSpeed = dt > 0f ? moved.magnitude / dt : 0f;
            if (Moving) AddNoise(Running ? 0.8f : Sneaking ? 0f : 0.25f);
            if (landT > 0f) landT -= dt;

            UpdateSurface();
            FindJumpTarget();
            if (GameInput.Jump)
            {
                if (hasTarget) StartJump(target, targetUp);
                else if (cc.isGrounded) vy = 2.2f; // a little hop in place
            }
            PlayAnim();
        }

        void UpdateSurface()
        {
            if (!Physics.SphereCast(transform.position + Vector3.up * 0.08f, 0.03f, Vector3.down, out var hit, 0.2f, Mask, QueryTriggerInteraction.Ignore)) return;
            var s = hit.collider.GetComponentInParent<Surface>();
            string id = s ? s.id : "floor";
            if (id == SurfaceId) return;
            SurfaceId = id;
            SurfaceChanged?.Invoke(id);
        }

        // ---------- aimed jump ----------

        void FindJumpTarget()
        {
            hasTarget = false;
            if (!Sniffing && cc.isGrounded)
            {
                Vector3 p0 = transform.position, f = transform.forward;
                for (float d = 0.14f; d <= maxJumpReach && !hasTarget; d += 0.04f)
                {
                    Vector3 o = p0 + f * d + Vector3.up * (maxJumpUp + 0.2f);
                    if (!Physics.Raycast(o, Vector3.down, out var hit, maxJumpUp + 0.7f, Mask, QueryTriggerInteraction.Ignore)) continue;
                    float dy = hit.point.y - p0.y;
                    if (dy > 0.07f && dy <= maxJumpUp && hit.normal.y > 0.75f && Clear(hit.point) && PathClear(p0, hit.point))
                    {
                        target = Inward(hit.point, f);
                        targetUp = true;
                        hasTarget = true;
                    }
                }
                if (!hasTarget && SurfaceId != "floor")
                {
                    for (float d = 0.12f; d <= 0.6f; d += 0.04f)
                    {
                        Vector3 o = p0 + f * d + Vector3.up * 0.1f;
                        if (!Physics.Raycast(o, Vector3.down, out var hit, 4f, Mask, QueryTriggerInteraction.Ignore)) continue;
                        if (p0.y - hit.point.y <= 0.12f) continue;
                        if (hit.normal.y > 0.75f && Clear(hit.point))
                        {
                            target = hit.point;
                            targetUp = false;
                            hasTarget = true;
                        }
                        break;
                    }
                }
            }
            ShowMarker(hasTarget);
        }

        Vector3 Inward(Vector3 p, Vector3 f)
        {
            // land a little past the edge rather than right on it
            Vector3 o = p + f * 0.08f + Vector3.up * 0.2f;
            if (Physics.Raycast(o, Vector3.down, out var hit, 0.4f, Mask, QueryTriggerInteraction.Ignore) && Mathf.Abs(hit.point.y - p.y) < 0.03f && Clear(hit.point))
                return hit.point;
            return p;
        }

        static bool Clear(Vector3 p) => !Physics.CheckSphere(p + Vector3.up * 0.08f, 0.05f, Mask, QueryTriggerInteraction.Ignore);

        static bool PathClear(Vector3 a, Vector3 b)
        {
            Vector3 up = new Vector3(a.x, b.y + 0.12f, a.z);
            return !Physics.Linecast(a + Vector3.up * 0.1f, up, Mask, QueryTriggerInteraction.Ignore)
                && !Physics.Linecast(up, b + Vector3.up * 0.12f, Mask, QueryTriggerInteraction.Ignore);
        }

        void ShowMarker(bool on)
        {
            if (!marker) return;
            if (marker.gameObject.activeSelf != on) marker.gameObject.SetActive(on);
            if (on) marker.position = target + Vector3.up * 0.004f;
        }

        void StartJump(Vector3 to, bool up)
        {
            jumping = true;
            jumpUp = up;
            cc.enabled = false;
            jumpFrom = transform.position;
            jumpTo = to;
            jumpT = 0f;
            jumpDur = Mathf.Clamp(0.3f + Vector3.Distance(jumpFrom, jumpTo) * 0.35f, 0.35f, 0.8f);
            var flat = Vector3.ProjectOnPlane(jumpTo - jumpFrom, Vector3.up);
            if (flat.sqrMagnitude > 1e-4f) transform.rotation = Quaternion.LookRotation(flat);
            ShowMarker(false);
        }

        void TickJump(float dt)
        {
            jumpT += dt / jumpDur;
            float t = Mathf.Clamp01(jumpT);
            Vector3 p = Vector3.Lerp(jumpFrom, jumpTo, t);
            float dy = jumpTo.y - jumpFrom.y;
            p.y = jumpUp
                ? jumpFrom.y + dy * Mathf.Sin(t * Mathf.PI * 0.5f) + 0.25f * t * (1f - t)
                : jumpFrom.y + 0.1f * Mathf.Sin(t * Mathf.PI) + dy * t * t;
            transform.position = p;
            if (t < 1f) return;
            jumping = false;
            cc.enabled = true;
            vy = -0.5f;
            landT = 0.2f;
            AddNoise(jumpUp ? 0.15f : 0.35f);
            UpdateSurface();
        }

        // ---------- animation ----------

        void PlayAnim()
        {
            if (!anim) return;
            string clip;
            if (jumping) clip = jumpUp ? "jump_up" : "jump_down";
            else if (landT > 0f) clip = "land";
            else if (Sniffing) clip = "sniff";
            else if (Moving) clip = Running ? "run" : Sneaking ? "sneak" : carried.Count > 0 ? "carry_walk" : "walk";
            else clip = "idle";
            anim.Play(clip);
            float baseSpeed = Running ? runSpeed : Sneaking ? sneakSpeed : walkSpeed;
            anim.Speed = Moving && !jumping ? Mathf.Clamp(MoveSpeed / baseSpeed, 0.6f, 1.4f) : 1f;
        }
    }
}
