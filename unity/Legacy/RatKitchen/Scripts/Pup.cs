using UnityEngine;

/// <summary>Крысёнок: голодный — подпрыгивает и вертится, сытый — ест у кучки еды.</summary>
public class Pup : MonoBehaviour
{
    public Transform head;
    public Transform tailPivot;

    [HideInInspector] public bool eating;
    [HideInInspector] public Vector3 eatPos;
    [HideInInspector] public float eatYaw;

    Vector3 homePos;
    Quaternion homeRot;
    float phase;

    void Awake()
    {
        homePos = transform.position;
        homeRot = transform.rotation;
        phase = Random.value * 6f;
    }

    void Update()
    {
        float t = Time.time;
        if (eating)
        {
            transform.position = eatPos;
            transform.rotation = Quaternion.Euler(0f, eatYaw, 0f);
            if (head) head.localRotation = Quaternion.Euler(10f + Mathf.Abs(Mathf.Sin(t * 9f + phase)) * 20f, 0f, 0f);
        }
        else
        {
            float hop = Mathf.Abs(Mathf.Sin(t * 7f + phase));
            transform.position = homePos + Vector3.up * (hop > 0.75f ? (hop - 0.75f) * 0.1f : 0f);
            transform.rotation = homeRot * Quaternion.Euler(0f, Mathf.Sin(t * 3f + phase) * 20f, 0f);
            if (head) head.localRotation = Quaternion.Euler(-15f, 0f, 0f);
        }
        if (tailPivot) tailPivot.localRotation = Quaternion.Euler(0f, Mathf.Sin(t * 6f + phase) * 28f, 0f);
    }
}
