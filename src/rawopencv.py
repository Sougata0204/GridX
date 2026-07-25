import cv2
import mediapipe as mp
import numpy as np
import math
import random

# Initialize MediaPipe
mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils
hands = mp_hands.Hands(max_num_hands=2, min_detection_confidence=0.7, min_tracking_confidence=0.7)

cap = cv2.VideoCapture(0)

# State tracking for Shields & Blasts
hand_states = {
    "Left": {"angle": 0, "particles": [], "blasting": False, "blast_r": 0, "prev_open": False, "center": (0,0)},
    "Right": {"angle": 0, "particles": [], "blasting": False, "blast_r": 0, "prev_open": False, "center": (0,0)}
}

# Global Portal State
portal_active = False
portal_radius = 0
portal_max_radius = 180
portal_center = (0, 0)
portal_sparks = []

def draw_magic_shield(canvas, center, radius, current_angle, is_time_stone):
    cx, cy = center
    if radius < 10: return (0, 0, 0)

    if is_time_stone:
        shield_color = (0, 255, 0)       
        inner_glow = (100, 255, 100)     
        current_angle = -current_angle   
    else:
        shield_color = (0, 140, 255)     
        inner_glow = (0, 215, 255)       
    
    cv2.circle(canvas, (cx, cy), int(radius * 1.2), shield_color, 2, cv2.LINE_AA)
    cv2.circle(canvas, (cx, cy), radius, shield_color, 3, cv2.LINE_AA)
    
    for i in range(12):
        rune_rad = math.radians(i * 30 + current_angle * 1.5)
        rx = int(cx + (radius * 1.3) * math.cos(rune_rad))
        ry = int(cy + (radius * 1.3) * math.sin(rune_rad))
        cv2.circle(canvas, (rx, ry), 3, inner_glow, -1)

    pts1, pts2 = [], []
    for i in range(6):
        rad1 = math.radians(i * 60 + current_angle)
        rad2 = math.radians(i * 60 - current_angle + 30)
        pts1.append([int(cx + radius * math.cos(rad1)), int(cy + radius * math.sin(rad1))])
        pts2.append([int(cx + radius * math.cos(rad2)), int(cy + radius * math.sin(rad2))])
        
    cv2.polylines(canvas, [np.array(pts1, np.int32)], True, shield_color, 2, cv2.LINE_AA)
    cv2.polylines(canvas, [np.array(pts2, np.int32)], True, inner_glow, 1, cv2.LINE_AA)
    cv2.circle(canvas, (cx, cy), int(radius * 0.6), shield_color, 2, cv2.LINE_AA)
    
    return shield_color

while True:
    success, img = cap.read()
    if not success: continue

    img = cv2.flip(img, 1)
    h, w, c = img.shape
    
    magic_canvas = np.zeros((h, w, 3), dtype=np.uint8)
    portal_canvas = np.zeros((h, w, 3), dtype=np.uint8)
    
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    results = hands.process(img_rgb)
    
    active_shield_centers = []
    any_hand_casting_portal = False
    detected_portal_center = (w // 2, h // 2)

    if results.multi_hand_landmarks:
        for idx, handLms in enumerate(results.multi_hand_landmarks):
            try:
                label = results.multi_handedness[idx].classification[0].label
                state = hand_states[label]
                
                # Finger calculation
                index_up = handLms.landmark[8].y < handLms.landmark[6].y
                middle_up = handLms.landmark[12].y < handLms.landmark[10].y
                ring_down = handLms.landmark[16].y > handLms.landmark[14].y
                pinky_down = handLms.landmark[20].y > handLms.landmark[18].y
                
                is_open_hand = index_up and middle_up and not ring_down and not pinky_down
                is_sling_ring_gesture = index_up and middle_up and ring_down and pinky_down

                wrist, index_mcp, pinky_mcp = handLms.landmark[0], handLms.landmark[5], handLms.landmark[17]
                cx = int((wrist.x + index_mcp.x + pinky_mcp.x) / 3 * w)
                cy = int((wrist.y + index_mcp.y + pinky_mcp.y) / 3 * h)
                mid_mcp = handLms.landmark[9]
                radius = int(math.hypot((mid_mcp.x - wrist.x) * w, (mid_mcp.y - wrist.y) * h) * 1.3)

                if is_sling_ring_gesture:
                    any_hand_casting_portal = True
                    detected_portal_center = (cx, cy - 50)

                if is_open_hand:
                    state["prev_open"] = True
                    state["center"] = (cx, cy)
                    active_shield_centers.append((cx, cy))
                    
                    if 10 < radius < 500: # Safe range check
                        is_time_stone = handLms.landmark[9].y > handLms.landmark[0].y
                        color = draw_magic_shield(magic_canvas, (cx, cy), radius, state["angle"], is_time_stone)
                        state["angle"] += 4 
                        
                        for _ in range(2):
                            rand_angle = random.uniform(0, 2 * math.pi)
                            state["particles"].append([
                                cx + radius * math.cos(rand_angle), cy + radius * math.sin(rand_angle),
                                math.cos(rand_angle) * random.uniform(2, 5), math.sin(rand_angle) * random.uniform(2, 5),
                                random.randint(10, 20), 20, color
                            ])
                else:
                    if state["prev_open"]:
                        state["blasting"] = True
                        state["blast_r"] = radius 
                        state["prev_open"] = False

                for p in state["particles"][:]:
                    p[0] += p[2]; p[1] += p[3]; p[4] -= 1    
                    if p[4] <= 0: state["particles"].remove(p)
                    else: cv2.circle(magic_canvas, (int(p[0]), int(p[1])), int(4 * (p[4]/p[5])), p[6], -1)

                if state["blasting"]:
                    cv2.circle(magic_canvas, state["center"], int(state["blast_r"]), (255, 255, 255), max(1, int(40 - state["blast_r"]/10)))
                    state["blast_r"] += 35
                    if state["blast_r"] > max(w, h): state["blasting"] = False
            except Exception:
                continue

    # Portal logic
    if any_hand_casting_portal:
        if not portal_active:
            portal_active = True
            portal_center = detected_portal_center
        if portal_radius < portal_max_radius: portal_radius += 10
        for _ in range(8):
            p_ang = random.uniform(0, 2 * math.pi)
            r_noise = random.uniform(-8, 8)
            px = portal_center[0] + (portal_radius + r_noise) * math.cos(p_ang)
            py = portal_center[1] + (portal_radius + r_noise) * math.sin(p_ang)
            spin_speed = random.uniform(4, 8)
            vx = -math.sin(p_ang) * spin_speed + random.uniform(-1, 1)
            vy = math.cos(p_ang) * spin_speed + random.uniform(-1, 1)
            life = random.randint(15, 30)
            portal_sparks.append([px, py, vx, vy, life, life])
    elif portal_radius > 0:
        portal_radius -= 15
        if portal_radius <= 0: portal_radius = 0; portal_active = False

    for ps in portal_sparks[:]:
        ps[0] += ps[2]; ps[1] += ps[3]; ps[4] -= 1
        if ps[4] <= 0 or portal_radius == 0: portal_sparks.remove(ps)
        else:
            pct = ps[4] / ps[5]
            cv2.circle(portal_canvas, (int(ps[0]), int(ps[1])), int(5 * pct), (0, int(120 * pct + 100), 255) if pct > 0.4 else (0, 60, 200), -1)

    if portal_active and portal_radius > 10:
        dimension_view = cv2.bitwise_not(img)
        dimension_view[:, :, 0] = cv2.add(dimension_view[:, :, 0], 80) 
        portal_mask = np.zeros((h, w), dtype=np.uint8)
        cv2.circle(portal_mask, portal_center, portal_radius, 255, -1)
        inverse_mask = cv2.bitwise_not(portal_mask)
        img = cv2.add(cv2.bitwise_and(img, img, mask=inverse_mask), cv2.bitwise_and(dimension_view, dimension_view, mask=portal_mask))

    # Ultimate Attack: Dual-Hand Energy Beam
    if len(active_shield_centers) == 2:
        # Calculate the distance between your two shields
        dist = math.hypot(active_shield_centers[0][0] - active_shield_centers[1][0], 
                          active_shield_centers[0][1] - active_shield_centers[1][1])
        
        # If hands are brought together (charging the beam)
        if dist < 160:
            # 1. Calculate Beam Origin (The exact midpoint between your hands)
            mid_x = (active_shield_centers[0][0] + active_shield_centers[1][0]) // 2
            mid_y = (active_shield_centers[0][1] + active_shield_centers[1][1]) // 2
            
            # 2. Draw the massive energy column shooting upward (BGR color format)
            # Outer deep blue aura
            cv2.line(magic_canvas, (mid_x, mid_y), (mid_x, 0), (255, 100, 0), 180, cv2.LINE_AA)
            # Inner bright cyan aura
            cv2.line(magic_canvas, (mid_x, mid_y), (mid_x, 0), (255, 200, 0), 120, cv2.LINE_AA)
            # Core white-hot beam
            cv2.line(magic_canvas, (mid_x, mid_y), (mid_x, 0), (255, 255, 255), 60, cv2.LINE_AA)
            
            # 3. Add an energy sphere charging at the palms
            cv2.circle(magic_canvas, (mid_x, mid_y), 90, (255, 200, 0), 15)
            cv2.circle(magic_canvas, (mid_x, mid_y), 60, (255, 255, 255), -1)
            
            # 4. Screen Shake Physics (Earthquake effect)
            # Generate random pixel offsets
            shake_intensity = 20
            dx = random.randint(-shake_intensity, shake_intensity)
            dy = random.randint(-shake_intensity, shake_intensity)
            
            # Create and apply an affine transformation matrix to physically shift the video feed
            M = np.float32([[1, 0, dx], [0, 1, dy]])
            img = cv2.warpAffine(img, M, (w, h))

    final_output = cv2.add(cv2.add(img, cv2.GaussianBlur(magic_canvas, (5, 5), 0)), cv2.GaussianBlur(portal_canvas, (3, 3), 0))
    cv2.imshow("Sorcerer Supreme V4 - Portal Edition", final_output)

    if cv2.waitKey(1) & 0xFF == ord('q'): break

cap.release()
cv2.destroyAllWindows()