using UnityEngine;

namespace KitchenRat
{
    /// <summary>Marks furniture the rat can stand on: "chair", "table", "counter"… Tasks like "Jump onto a chair" check this id.</summary>
    public class Surface : MonoBehaviour
    {
        public string id = "floor";
    }
}
