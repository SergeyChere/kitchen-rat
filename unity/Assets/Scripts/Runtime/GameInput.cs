using UnityEngine;
#if ENABLE_INPUT_SYSTEM && !ENABLE_LEGACY_INPUT_MANAGER
using UnityEngine.InputSystem;
#endif

namespace KitchenRat
{
    /// <summary>All controls in one place. Works with both the old Input Manager and the Input System package.</summary>
    public static class GameInput
    {
#if ENABLE_INPUT_SYSTEM && !ENABLE_LEGACY_INPUT_MANAGER
        static Keyboard K => Keyboard.current;
        static Mouse M => Mouse.current;
        static bool Held(Key k) => K != null && K[k].isPressed;
        static bool Pressed(Key k) => K != null && K[k].wasPressedThisFrame;

        public static Vector2 Move => Vector2.ClampMagnitude(new Vector2(
            (Held(Key.D) || Held(Key.RightArrow) ? 1 : 0) - (Held(Key.A) || Held(Key.LeftArrow) ? 1 : 0),
            (Held(Key.W) || Held(Key.UpArrow) ? 1 : 0) - (Held(Key.S) || Held(Key.DownArrow) ? 1 : 0)), 1f);
        public static Vector2 Look => M == null ? Vector2.zero : M.delta.ReadValue() * 0.1f;
        public static float Zoom => M == null ? 0f : M.scroll.ReadValue().y / 120f;
        public static bool Run => Held(Key.LeftShift) || Held(Key.RightShift);
        public static bool SneakHeld => Held(Key.LeftCtrl) || Held(Key.RightCtrl);
        public static bool SneakToggle => Pressed(Key.C);
        public static bool Jump => Pressed(Key.Space);
        public static bool Sniff => Held(Key.E) || (M != null && M.rightButton.isPressed);
        public static bool Push => Pressed(Key.F);
        public static bool Pause => Pressed(Key.Escape);
        public static bool Restart => Pressed(Key.R);
        public static bool Click => M != null && M.leftButton.wasPressedThisFrame;
#else
        public static Vector2 Move => Vector2.ClampMagnitude(new Vector2(
            (Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.RightArrow) ? 1 : 0) - (Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.LeftArrow) ? 1 : 0),
            (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow) ? 1 : 0) - (Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow) ? 1 : 0)), 1f);
        public static Vector2 Look => new Vector2(Input.GetAxisRaw("Mouse X"), Input.GetAxisRaw("Mouse Y"));
        public static float Zoom => Input.mouseScrollDelta.y;
        public static bool Run => Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
        public static bool SneakHeld => Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
        public static bool SneakToggle => Input.GetKeyDown(KeyCode.C);
        public static bool Jump => Input.GetKeyDown(KeyCode.Space);
        public static bool Sniff => Input.GetKey(KeyCode.E) || Input.GetMouseButton(1);
        public static bool Push => Input.GetKeyDown(KeyCode.F);
        public static bool Pause => Input.GetKeyDown(KeyCode.Escape);
        public static bool Restart => Input.GetKeyDown(KeyCode.R);
        public static bool Click => Input.GetMouseButtonDown(0);
#endif
    }
}
