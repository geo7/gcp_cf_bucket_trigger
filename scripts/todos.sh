# Simply dumps todo's out with a little context, will have to open some of them
# in the editor to view more, typically used via make.
rg '^\s*#.*TODO.*$' -A 3
