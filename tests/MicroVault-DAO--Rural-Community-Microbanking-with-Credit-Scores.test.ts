import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;

/*
  Basic tests for MicroVault DAO contract with Community Savings Groups feature
*/

describe("MicroVault DAO Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("allows user registration", () => {
    const { result } = simnet.callPublicFn("MicroVault-DAO--Rural-Community-Microbanking-with-Credit-Scores", "register-user", [], address1);
    expect(result).toBeOk(true);
  });

  it("allows creating savings groups", () => {
    const { result } = simnet.callPublicFn("MicroVault-DAO--Rural-Community-Microbanking-with-Credit-Scores", "create-savings-group", 
      ["Village Savings", "Community savings group", 30], address1);
    expect(result).toBeOk(1);
  });

  it("can read contract data", () => {
    const { result } = simnet.callReadOnlyFn("MicroVault-DAO--Rural-Community-Microbanking-with-Credit-Scores", "get-user-data", [address1], address1);
    expect(result).toBeDefined();
  });
});
