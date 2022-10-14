
# Use `fast .version_up` to rewrite the version file
Fast.shortcut :version_up do
  rewrite_file('(casgn nil VERSION (str _)', 'lib/timescaledb/version.rb') do |node|
    target = node.children.last.loc.expression
    pieces = target.source.split('.').map(&:to_i)
    pieces.reverse.each_with_index do |fragment, i|
      if fragment < 9
        pieces[-(i + 1)] = fragment + 1
        break
      else
        pieces[-(i + 1)] = 0
      end
    end
    replace(target, "'#{pieces.join('.')}'")
  end
end
