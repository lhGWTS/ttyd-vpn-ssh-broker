# Convenience wrapper. Requires ansible-core + the community.general collection
# on the control node (see README).
INV := -i inventory.ini

.PHONY: rebuild check bootstrap provision teardown ping

# Full cold rebuild of a fresh thm container: add python3, provision, drop python3.
rebuild: bootstrap provision teardown

bootstrap:
	ansible-playbook $(INV) bootstrap.yml

provision:
	ansible-playbook $(INV) site.yml

# Dry run (needs python3 present, i.e. run `make bootstrap` first).
check:
	ansible-playbook $(INV) site.yml --check --diff

teardown:
	ansible-playbook $(INV) teardown.yml

ping:
	ansible $(INV) thm -m raw -a 'echo ok'
