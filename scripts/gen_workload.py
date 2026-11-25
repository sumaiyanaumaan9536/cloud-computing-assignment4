import random
random.seed()
with open("results/milestone4/workload.txt", "w") as f:
    for _ in range(1000):
        P = random.randint(100000, 1000000)
        rate = random.randint(5, 20)
        n = random.randint(12, 60)
        f.write("/api/emi method=POST contents='{\"P\":%d,\"rate\":%d,\"n\":%d}'\n\n" % (P, rate, n))
