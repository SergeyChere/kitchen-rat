using UnityEngine;

/// <summary>Крошка или сыр. Пока лежит на полу, слегка покачивается, чтобы её было видно.</summary>
public class FoodItem : MonoBehaviour
{
    [Tooltip("Сколько еды получают крысята")] public int value = 1;
    [Tooltip("Сколько места занимает в зубах (максимум у крысы 3)")] public int weight = 1;

    /// <summary>true — в зубах у крысы или уже лежит в норе (не качается).</summary>
    [HideInInspector] public bool carried;

    float phase;
    Vector3 basePos;

    void Awake() { phase = Random.value * 10f; }

    public void PlaceOnFloor(Vector3 p)
    {
        carried = false;
        transform.SetParent(null);
        basePos = p;
        transform.position = p;
    }

    void Update()
    {
        if (carried) return;
        transform.position = basePos + Vector3.up * (Mathf.Sin(Time.time * 3f + phase) * 0.015f);
        transform.Rotate(0f, 45f * Time.deltaTime, 0f, Space.World);
    }
}
