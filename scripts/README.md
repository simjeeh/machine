# Scripts
## Initializing Manjaro
```
sudo pacman -S git

# Add credentials
# https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
ssh-keygen -t ed25519 -C "your_email@example.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account
cat ~/.ssh/id_ed25519.pub
# Add to https://github.com/settings/keys

mkdir ${HOME}/workspace
cd ${HOME}/workspace
git clone git@github.com:simjeeh/scripts.git
cd scripts
sudo bash init.sh
```
