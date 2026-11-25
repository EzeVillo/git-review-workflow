setup_suite() {
	# The legacy suites exercise reviews already using the current checkout.
	# Managed-workspace cases explicitly select the new behavior.
	export GIT_REVIEW_CHECKOUT=current
}
