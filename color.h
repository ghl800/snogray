#ifndef __COLOR_H__
#define __COLOR_H__

#include <fstream>

class Color
{
public:
  typedef float component_t;

  Color (component_t _red, component_t _green, component_t _blue)
    { red = _red; green = _green; blue = _blue; }
  Color ()
    { red = green = blue = 0; }

  Color lit_by (const Color &light_color) const
  {
    return Color (red * light_color.red,
		  green * light_color.green,
		  blue * light_color.blue);
  }

  Color operator* (float scale) const
  {
    return Color (red * scale, green * scale, blue * scale);
  }

  component_t red, green, blue;

  static const Color black;
};

extern std::ostream& operator<< (std::ostream &os, const Color &col);

#endif /* __COLOR_H__ */

// arch-tag: 389b3ebb-55a4-4d70-afbe-91bdb72d28ed
