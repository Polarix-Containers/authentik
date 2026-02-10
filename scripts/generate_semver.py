# Dummy python script invoked by Makefile
# to generate a version number

# Upstream's code does not work in our workflow for whatever reason,
# so we provide our own

import os
print(os.environ['TAG'])
