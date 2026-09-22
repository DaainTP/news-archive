# SketchUp Ruby API 최소 모의(stub) 구현
# 목적: SketchUp 이 없는 환경에서 drawkit.rb 의 로직(단위환산/좌표/바운딩박스/검증)을 검사한다.
# 실제 SketchUp 의 동작을 전부 재현하지는 않는다. 형상 종류는 평면 폴리곤 + Z방향 압출만 다룬다.

class Numeric
  def mm; self / 25.4; end          # mm -> inch (SketchUp 내부단위는 inch)
  def to_mm; self * 25.4; end
end

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
    def to_a; [@x, @y, @z]; end
  end

  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
  end
end

module Length
  Decimal = 0; Architectural = 1; Engineering = 2; Fractional = 3
  Inches = 0; Feet = 1; Millimeter = 2; Centimeter = 3; Meter = 4
end

module Sketchup
  class Edge
    attr_reader :a, :b
    def initialize(a, b); @a, @b = a, b; end
    def vertices; [@a, @b]; end
  end

  class Face
    attr_reader :pts, :dist
    def initialize(pts); @pts = pts; @dist = 0.0; end

    # Newell's method
    def normal
      nx = ny = nz = 0.0
      n = @pts.size
      n.times do |i|
        p1 = @pts[i]; p2 = @pts[(i + 1) % n]
        nx += (p1.y - p2.y) * (p1.z + p2.z)
        ny += (p1.z - p2.z) * (p1.x + p2.x)
        nz += (p1.x - p2.x) * (p1.y + p2.y)
      end
      len = Math.sqrt(nx * nx + ny * ny + nz * nz)
      len.zero? ? Geom::Vector3d.new(0, 0, 0) : Geom::Vector3d.new(nx / len, ny / len, nz / len)
    end

    def reverse!; @pts.reverse!; self; end
    def pushpull(d); @dist = d.to_f; self; end

    def extruded_points
      nv = normal
      @pts + @pts.map { |p| Geom::Point3d.new(p.x + nv.x * @dist, p.y + nv.y * @dist, p.z + nv.z * @dist) }
    end
  end

  class BoundingBox
    def initialize(pts)
      if pts.empty?
        @lo = [0.0, 0.0, 0.0]; @hi = [0.0, 0.0, 0.0]
      else
        xs = pts.map(&:x); ys = pts.map(&:y); zs = pts.map(&:z)
        @lo = [xs.min, ys.min, zs.min]; @hi = [xs.max, ys.max, zs.max]
      end
    end
    def min; Geom::Point3d.new(*@lo); end
    def max; Geom::Point3d.new(*@hi); end
    def width;  @hi[0] - @lo[0]; end   # X
    def height; @hi[1] - @lo[1]; end   # Y
    def depth;  @hi[2] - @lo[2]; end   # Z
  end

  class Entities
    def initialize; @items = []; end
    def each(&b); @items.each(&b); end
    def to_a; @items; end
    def grep(klass); @items.grep(klass); end
    def size; @items.size; end
    def snapshot; @items.dup; end
    def restore!(snap); @items = snap; end

    def add_group
      g = Group.new
      @items << g
      g
    end

    def add_face(*args)
      flat = args.flatten
      pts = if flat.first.is_a?(Edge)
              flat.map { |e| e.vertices.first }
            else
              flat
            end
      f = Face.new(pts)
      @items << f
      f
    end

    def add_circle(center, normal, radius, segments = 24)
      r = radius.to_f
      pts = (0...segments).map do |i|
        a = 2 * Math::PI * i / segments
        Geom::Point3d.new(center.x + r * Math.cos(a), center.y + r * Math.sin(a), center.z)
      end
      edges = (0...segments).map { |i| Edge.new(pts[i], pts[(i + 1) % segments]) }
      @items.concat(edges)
      edges
    end
  end

  class Group
    attr_accessor :name, :material, :layer
    def initialize; @entities = Entities.new; @name = ""; end
    def entities; @entities; end
    def bounds; BoundingBox.new(collect_points); end

    def collect_points
      pts = []
      @entities.each do |e|
        case e
        when Face  then pts.concat(e.extruded_points)
        when Group then pts.concat(e.collect_points)
        end
      end
      pts
    end
  end

  class Model
    attr_reader :saved_path, :operations
    def initialize
      @entities = Entities.new
      @options = { "UnitsOptions" => {} }
      @operations = []
    end
    def entities; @entities; end
    def active_entities; @entities; end
    def options; @options; end
    # 실제 SketchUp 과 동일하게, abort 시 연산 시작 시점으로 되돌린다.
    def start_operation(name, _disable_ui = false)
      @operations << [:start, name]
      @snapshot = @entities.snapshot
      true
    end

    def commit_operation
      @operations << [:commit]
      @snapshot = nil
      true
    end

    def abort_operation
      @operations << [:abort]
      @entities.restore!(@snapshot) if @snapshot
      @snapshot = nil
      true
    end
    def save(path); @saved_path = path; true; end
  end

  def self.active_model; @model ||= Model.new; end
  def self.reset_model!; @model = Model.new; end
end
