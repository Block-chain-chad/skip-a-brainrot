-- CodeConfig: redeemable promo codes. SERVER-ONLY on purpose — keep this module in
-- ServerScriptService so clients can't read the code list. Add/retire codes here.
-- Reward fields: Cash (number).
return {
	WELCOME = { Cash = 2500 },
	BRAINROT = { Cash = 5000 },
	LAKETAHOE = { Cash = 10000 },
	SKIPMASTER = { Cash = 25000 },
}
