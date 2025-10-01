// Rating Hook para gerenciar seleção de avaliação
const RatingHook = {
  mounted() {
    this.addRatingButtonListeners();
  },

  updated() {
    this.addRatingButtonListeners();
  },

  addRatingButtonListeners() {
    const ratingButtons = this.el.querySelectorAll('button[data-rating]');
    
    ratingButtons.forEach((button) => {
      button.removeEventListener('click', this.handleRatingClick);
      
      button.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        
        const rating = event.target.getAttribute('data-rating');
        this.pushEvent('update_rating_value', { value: rating });
      });
    });
  },

  handleRatingClick(event) {
    // Handler vazio para compatibilidade
  }
};

export default RatingHook;
