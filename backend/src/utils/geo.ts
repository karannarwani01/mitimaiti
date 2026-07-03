/**
 * Haversine formula for calculating distance between two coordinates.
 * Returns distance in kilometers.
 */
export function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371; // Earth radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c);
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}

/**
 * City coordinate lookup for common Sindhi diaspora cities worldwide.
 * Returns [latitude, longitude] or null if city not found.
 */
const CITY_COORDS: Record<string, [number, number]> = {
  // India
  'Mumbai': [19.076, 72.8777],
  'Delhi': [28.7041, 77.1025],
  'Pune': [18.5204, 73.8567],
  'Hyderabad': [17.385, 78.4867],
  'Bangalore': [12.9716, 77.5946],
  'Ahmedabad': [23.0225, 72.5714],
  'Chennai': [13.0827, 80.2707],
  'Kolkata': [22.5726, 88.3639],
  'Jaipur': [26.9124, 75.7873],
  'Lucknow': [26.8467, 80.9462],
  'Indore': [22.7196, 75.8577],
  'Surat': [21.1702, 72.8311],
  'Vadodara': [22.3072, 73.1812],
  'Rajkot': [22.3039, 70.8022],
  'Nagpur': [21.1458, 79.0882],
  'Thane': [19.2183, 72.9781],
  'Gurgaon': [28.4595, 77.0266],
  'Noida': [28.5355, 77.391],
  'Chandigarh': [30.7333, 76.7794],
  'Jodhpur': [26.2389, 73.0243],
  'Udaipur': [24.5854, 73.7125],
  'Adipur': [23.0747, 70.1757],
  'Gandhidham': [23.0753, 70.1337],
  'Ulhasnagar': [19.2183, 73.1631],
  // UAE
  'Dubai': [25.2048, 55.2708],
  'Abu Dhabi': [24.4539, 54.3773],
  'Sharjah': [25.3463, 55.4209],
  // USA
  'New York': [40.7128, -74.006],
  'Los Angeles': [34.0522, -118.2437],
  'Chicago': [41.8781, -87.6298],
  'Houston': [29.7604, -95.3698],
  'San Francisco': [37.7749, -122.4194],
  'San Jose': [37.3382, -121.8863],
  'Dallas': [32.7767, -96.797],
  'Atlanta': [33.749, -84.388],
  'Seattle': [47.6062, -122.3321],
  'Boston': [42.3601, -71.0589],
  'Miami': [25.7617, -80.1918],
  'Washington': [38.9072, -77.0369],
  // UK
  'London': [51.5074, -0.1278],
  'Birmingham': [52.4862, -1.8904],
  'Manchester': [53.4808, -2.2426],
  'Leicester': [52.6369, -1.1398],
  // Canada
  'Toronto': [43.6532, -79.3832],
  'Vancouver': [49.2827, -123.1207],
  'Calgary': [51.0447, -114.0719],
  // Singapore, Hong Kong, Sydney
  'Singapore': [1.3521, 103.8198],
  'Hong Kong': [22.3193, 114.1694],
  'Sydney': [-33.8688, 151.2093],
  'Melbourne': [-37.8136, 144.9631],
  // Pakistan (Sindh)
  'Karachi': [24.8607, 67.0011],
  'Hyderabad Sindh': [25.396, 68.3578],
  'Sukkur': [27.7052, 68.8574],
  'Larkana': [27.5595, 68.2141],
  // Other
  'Nairobi': [-1.2921, 36.8219],
  'Lagos': [6.5244, 3.3792],
  'Muscat': [23.588, 58.3829],
  'Doha': [25.2854, 51.531],
  'Bahrain': [26.0667, 50.5577],
  'Kuwait City': [29.3759, 47.9774],
};

/**
 * Get coordinates for a city name (case-insensitive).
 *
 * Falls back to a whole-word containment match in ONE direction only: the
 * user's string must contain the known city as a whole word ("Navi Mumbai"
 * → Mumbai, "Bur Dubai" → Dubai). The old bidirectional raw-substring match
 * returned wrong coordinates for short inputs ("York" → New York, "Sur" →
 * Surat), silently corrupting distance ranking.
 */
export function getCityCoords(city: string): [number, number] | null {
  if (!city) return null;
  const normalized = city.trim().toLowerCase();

  // Exact match first
  for (const [name, coords] of Object.entries(CITY_COORDS)) {
    if (name.toLowerCase() === normalized) return coords;
  }

  // Whole-word containment: input contains the known city name
  for (const [name, coords] of Object.entries(CITY_COORDS)) {
    const key = name.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp(`(^|[\\s,\\-/])${key}($|[\\s,\\-/])`).test(normalized)) {
      return coords;
    }
  }

  return null;
}

/**
 * Calculate distance between two cities by name.
 * Returns distance in km, or null if either city is not found.
 */
export function cityDistance(city1: string, city2: string): number | null {
  const coords1 = getCityCoords(city1);
  const coords2 = getCityCoords(city2);
  if (!coords1 || !coords2) return null;
  if (city1.toLowerCase() === city2.toLowerCase()) return 0;
  return haversineDistance(coords1[0], coords1[1], coords2[0], coords2[1]);
}
