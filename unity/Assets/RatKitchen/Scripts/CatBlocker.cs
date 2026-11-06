using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Невидимая стенка, которая не пускает кота под стол и стулья.
/// Крыса проходит сквозь неё (GameManager отключает столкновения с крысой).
/// </summary>
[RequireComponent(typeof(BoxCollider))]
public class CatBlocker : MonoBehaviour
{
    public static readonly List<Collider> All = new List<Collider>();

    void OnEnable() { All.Add(GetComponent<Collider>()); }
    void OnDisable() { All.Remove(GetComponent<Collider>()); }
}
